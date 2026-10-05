//    io/fd-win32.cpp - io::FD on Windows (Winsock sockets, CRT files)
//
//    This file is part of Aethyra, derived from The Mana World (Athena server)
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <http://www.gnu.org/licenses/>.

// The server indexes its session table by descriptor number and expects
// files and sockets to share one descriptor space, as on POSIX. Winsock
// SOCKETs are opaque handles, so here:
//
//   0..2                     the CRT's stdin/stdout/stderr
//   3..MAX_SOCKETS-1         slots holding Winsock SOCKETs
//   MAX_SOCKETS + n          CRT file descriptor n (n > 2)
//
// Errors are reported through errno, translated from WSAGetLastError().

#ifdef _WIN32

#include "fd.hpp"

#include <cerrno>

#include "../strings/zstring.hpp"

// Raise the native fd_set capacity (default 64) before Winsock sees it.
#define FD_SETSIZE 1024
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <fcntl.h>
#include <io.h>
#include <sys/stat.h>

#include "../poison.hpp"


namespace tmwa
{
namespace io
{
    static_assert(FD_SETSIZE >= MAX_SOCKETS, "native fd_set too small");

    static
    SOCKET slots[MAX_SOCKETS];
    static
    bool slots_ready = false;

    static
    void init_sockets()
    {
        if (slots_ready)
            return;
        WSADATA data;
        WSAStartup(MAKEWORD(2, 2), &data);
        for (SOCKET& s : slots)
            s = INVALID_SOCKET;
        slots_ready = true;
    }

    static
    bool is_socket(int fd)
    {
        return slots_ready && fd > 2 && fd < MAX_SOCKETS && slots[fd] != INVALID_SOCKET;
    }

    static
    int crt_fd(int fd)
    {
        if (0 <= fd && fd <= 2)
            return fd;
        if (fd >= MAX_SOCKETS)
            return fd - MAX_SOCKETS;
        return -1;
    }

    static
    int from_crt(int crt)
    {
        if (crt < 0)
            return -1;
        if (crt <= 2)
            return crt;
        return crt + MAX_SOCKETS;
    }

    static
    void set_errno_from_wsa()
    {
        switch (WSAGetLastError())
        {
        case WSAEWOULDBLOCK: errno = EWOULDBLOCK; break;
        case WSAEINPROGRESS: errno = EINPROGRESS; break;
        case WSAEINTR: errno = EINTR; break;
        case WSAECONNRESET: errno = ECONNRESET; break;
        case WSAECONNREFUSED: errno = ECONNREFUSED; break;
        case WSAECONNABORTED: errno = ECONNABORTED; break;
        case WSAENOTCONN: errno = ENOTCONN; break;
        case WSAEADDRINUSE: errno = EADDRINUSE; break;
        case WSAEMFILE: errno = EMFILE; break;
        case WSAENOTSOCK: errno = EBADF; break;
        default: errno = EIO; break;
        }
    }

    static
    int alloc_slot(SOCKET sock)
    {
        if (sock == INVALID_SOCKET)
        {
            set_errno_from_wsa();
            return -1;
        }
        for (int i = 3; i < MAX_SOCKETS; ++i)
        {
            if (slots[i] == INVALID_SOCKET)
            {
                slots[i] = sock;
                return i;
            }
        }
        closesocket(sock);
        errno = EMFILE;
        return -1;
    }

    static
    int socket_result(int rv)
    {
        if (rv == SOCKET_ERROR)
        {
            set_errno_from_wsa();
            return -1;
        }
        return rv;
    }

    FD FD::open(ZString path, int flags, int mode)
    {
        // Always binary: text mode would rewrite line endings and corrupt
        // binary data such as walk maps.
        int pmode = (mode & 0200) ? (_S_IREAD | _S_IWRITE) : _S_IREAD;
        return FD(from_crt(::_open(path.c_str(), flags | _O_BINARY, pmode)));
    }
    FD FD::openat(FD dirfd, ZString path, int flags, int mode)
    {
        // Only the current directory is supported; see dir.cpp.
        (void)dirfd;
        return open(path, flags, mode);
    }
    FD FD::socket(int domain, int type, int protocol)
    {
        init_sockets();
        return FD(alloc_slot(::socket(domain, type, protocol)));
    }
    FD FD::accept(struct sockaddr *addr, socklen_t *addrlen)
    {
        if (!is_socket(fd))
        {
            errno = EBADF;
            return FD();
        }
        return FD(alloc_slot(::accept(slots[fd], addr, addrlen)));
    }
    FD FD::sysconf_SC_OPEN_MAX()
    {
        return FD(MAX_SOCKETS);
    }

    ssize_t FD::read(void *buf, size_t count)
    {
        if (is_socket(fd))
            return recv(buf, count, 0);
        return ::_read(crt_fd(fd), buf, static_cast<unsigned>(count));
    }
    ssize_t FD::write(const void *buf, size_t count)
    {
        if (is_socket(fd))
            return send(buf, count, 0);
        return ::_write(crt_fd(fd), buf, static_cast<unsigned>(count));
    }
    ssize_t FD::send(const void *buf, size_t count, int flags)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::send(slots[fd], static_cast<const char *>(buf),
                    static_cast<int>(count), flags));
    }
    ssize_t FD::sendto(const void *buf, size_t count, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::sendto(slots[fd], static_cast<const char *>(buf),
                    static_cast<int>(count), flags, dest_addr, addrlen));
    }
    ssize_t FD::recv(void *buf, size_t count, int flags)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::recv(slots[fd], static_cast<char *>(buf),
                    static_cast<int>(count), flags));
    }
    ssize_t FD::recvfrom(void *buf, size_t count, int flags,
             struct sockaddr *src_addr, socklen_t *addrlen)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::recvfrom(slots[fd], static_cast<char *>(buf),
                    static_cast<int>(count), flags, src_addr, addrlen));
    }
    ssize_t FD::writev(const struct iovec *iov, int iovcnt)
    {
        ssize_t total = 0;
        for (int i = 0; i < iovcnt; ++i)
        {
            ssize_t rv = write(iov[i].iov_base, iov[i].iov_len);
            if (rv < 0)
                return total ? total : rv;
            total += rv;
            if (static_cast<size_t>(rv) < iov[i].iov_len)
                break;
        }
        return total;
    }

    int FD::close()
    {
        if (fd == -1)
        {
            errno = EBADF;
            return -1;
        }
        if (is_socket(fd))
        {
            SOCKET sock = slots[fd];
            slots[fd] = INVALID_SOCKET;
            return socket_result(::closesocket(sock));
        }
        return ::_close(crt_fd(fd));
    }
    int FD::shutdown(int how)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::shutdown(slots[fd], how));
    }
    int FD::getsockopt(int level, int optname, void *optval, socklen_t *optlen)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::getsockopt(slots[fd], level, optname,
                    static_cast<char *>(optval), optlen));
    }
    int FD::setsockopt(int level, int optname, const void *optval, socklen_t optlen)
    {
        if (!is_socket(fd))
        {
            errno = ENOTSOCK;
            return -1;
        }
        return socket_result(::setsockopt(slots[fd], level, optname,
                    static_cast<const char *>(optval), optlen));
    }
    int FD::fcntl(int cmd)
    {
        (void)cmd;
        errno = EINVAL;
        return -1;
    }
    int FD::fcntl(int cmd, int arg)
    {
        // The server only ever makes sockets non-blocking.
        if (cmd == F_SETFL && is_socket(fd))
        {
            u_long nonblocking = (arg & O_NONBLOCK) ? 1 : 0;
            return socket_result(::ioctlsocket(slots[fd], FIONBIO, &nonblocking));
        }
        errno = EINVAL;
        return -1;
    }
    int FD::fcntl(int cmd, void *arg)
    {
        (void)cmd;
        (void)arg;
        errno = EINVAL;
        return -1;
    }
    int FD::listen(int backlog)
    {
        return socket_result(::listen(slots[fd], backlog));
    }
    int FD::bind(const struct sockaddr *addr, socklen_t addrlen)
    {
        return socket_result(::bind(slots[fd], addr, addrlen));
    }
    int FD::connect(const struct sockaddr *addr, socklen_t addrlen)
    {
        int rv = socket_result(::connect(slots[fd], addr, addrlen));
        // Non-blocking connects report EWOULDBLOCK where POSIX says EINPROGRESS.
        if (rv == -1 && errno == EWOULDBLOCK)
            errno = EINPROGRESS;
        return rv;
    }
    FD FD::dup()
    {
        if (is_socket(fd))
        {
            errno = EINVAL;
            return FD();
        }
        return FD(from_crt(::_dup(crt_fd(fd))));
    }

    void FD_Set::clr(FD fd)
    {
        int f = fd.uncast_dammit();
        if (0 <= f && f < MAX_SOCKETS)
            fds.reset(f);
    }
    bool FD_Set::isset(FD fd)
    {
        int f = fd.uncast_dammit();
        return 0 <= f && f < MAX_SOCKETS && fds.test(f);
    }
    void FD_Set::set(FD fd)
    {
        int f = fd.uncast_dammit();
        if (0 <= f && f < MAX_SOCKETS)
            fds.set(f);
    }

    static
    void to_native(FD_Set *set, fd_set *native, const std::bitset<MAX_SOCKETS>& bits)
    {
        FD_ZERO(native);
        if (!set)
            return;
        for (int i = 3; i < MAX_SOCKETS; ++i)
            if (bits.test(i) && slots[i] != INVALID_SOCKET)
                FD_SET(slots[i], native);
    }

    int FD_Set::select(int nfds, FD_Set *readfds, FD_Set *writefds, FD_Set *exceptfds, struct timeval *timeout)
    {
        (void)nfds;
        init_sockets();

        std::bitset<MAX_SOCKETS> rbits, wbits, ebits;
        if (readfds)
            rbits = readfds->fds;
        if (writefds)
            wbits = writefds->fds;
        if (exceptfds)
            ebits = exceptfds->fds;

        fd_set rset, wset, eset;
        to_native(readfds, &rset, rbits);
        to_native(writefds, &wset, wbits);
        // A failed non-blocking connect is only reported in the exception
        // set on Windows. Watch readable sockets for it too and report them
        // readable, so the failing read closes the session as on POSIX.
        to_native(readfds, &eset, rbits | ebits);

        if (rset.fd_count == 0 && wset.fd_count == 0 && eset.fd_count == 0)
        {
            // Winsock rejects select() with no sockets; just wait.
            if (timeout)
                Sleep(static_cast<DWORD>(timeout->tv_sec * 1000 + timeout->tv_usec / 1000));
            return 0;
        }

        int rv = ::select(0, &rset, &wset, &eset, timeout);
        if (rv == SOCKET_ERROR)
        {
            set_errno_from_wsa();
            return -1;
        }

        if (readfds)
            readfds->fds.reset();
        if (writefds)
            writefds->fds.reset();
        if (exceptfds)
            exceptfds->fds.reset();
        for (int i = 3; i < MAX_SOCKETS; ++i)
        {
            if (slots[i] == INVALID_SOCKET)
                continue;
            bool failed = FD_ISSET(slots[i], &eset);
            if (readfds && rbits.test(i) && (FD_ISSET(slots[i], &rset) || failed))
                readfds->fds.set(i);
            if (writefds && wbits.test(i) && FD_ISSET(slots[i], &wset))
                writefds->fds.set(i);
            if (exceptfds && ebits.test(i) && failed)
                exceptfds->fds.set(i);
        }
        return rv;
    }
} // namespace io
} // namespace tmwa

#endif // _WIN32
