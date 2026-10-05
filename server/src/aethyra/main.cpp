//    aethyra/main.cpp - entry point to the combined Aethyra server
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

// Runs the login, char and map services in one process, sharing one event
// loop. They still talk to each other over loopback TCP exactly as the
// separate tmwa-* programs do, so the services stay unchanged; this only
// replaces the three processes a host would otherwise have to manage.
//
// Usage: aethyra-server [--world DIR] [--stop-file FILE] [--parent-pid PID]
//                       [--help] [--version]
//
// All configuration and save paths are relative to the world directory
// (default: the current directory).
//
// When the client hosts a world it passes --stop-file and --parent-pid.
// The server shuts down cleanly (saving everything) once the stop file
// exists or the client process is gone, so a crashed client cannot leave
// a server running in the background. This works the same on Windows,
// where a windowed program cannot send console control events to its
// child process.

#include <fcntl.h>

#include <cstdio>
#include <cstdlib>

#ifndef _WIN32
# include <signal.h>
# include <unistd.h>
#endif

#include "../high/core.hpp"

#include "../strings/astring.hpp"

#include "../io/cxxstdio.hpp"
#include "../io/fd.hpp"

#include "../net/timer.hpp"

#include "../char/char.hpp"
#include "../login/login.hpp"
#include "../map/map.hpp"

#include "../mmo/version.hpp"

#ifdef _WIN32
// After the server's headers, whose names collide with <windows.h> macros.
# define WIN32_LEAN_AND_MEAN
# define NOMINMAX
# include <windows.h>
# include <direct.h>
#endif

#include "../poison.hpp"


namespace tmwa
{
namespace aethyra
{
static
AString stop_file;
static
long parent_pid = 0;

static
bool parent_alive()
{
#ifdef _WIN32
    HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(parent_pid));
    if (!parent)
        return false;
    bool alive = WaitForSingleObject(parent, 0) == WAIT_TIMEOUT;
    CloseHandle(parent);
    return alive;
#else
    return kill(static_cast<pid_t>(parent_pid), 0) == 0;
#endif
}

static
void check_host(TimerData *, tick_t)
{
    if (stop_file)
    {
        io::FD f = io::FD::open(stop_file, O_RDONLY);
        if (f != io::FD())
        {
            f.close();
            remove(stop_file.c_str());
            PRINTF("Stop requested by the host; shutting down.\n"_fmt);
            runflag = false;
        }
    }
    if (parent_pid && !parent_alive())
    {
        PRINTF("Hosting client has exited; shutting down.\n"_fmt);
        runflag = false;
    }
}

static
int change_dir(ZString dir)
{
#ifdef _WIN32
    return _chdir(dir.c_str());
#else
    return chdir(dir.c_str());
#endif
}

static
int do_init(Slice<ZString> argv)
{
    ZString argv0 = argv.pop_front();
    while (argv)
    {
        ZString arg = argv.pop_front();
        if (arg == "--help"_s)
        {
            PRINTF("Usage: %s [--world DIR] [--stop-file FILE] [--parent-pid PID] [--help] [--version]\n"_fmt, argv0);
            exit(0);
        }
        else if (arg == "--version"_s)
        {
            PRINTF("%s\n"_fmt, CURRENT_VERSION_STRING);
            exit(0);
        }
        else if (arg == "--world"_s && argv)
        {
            ZString dir = argv.pop_front();
            if (change_dir(dir) != 0)
            {
                FPRINTF(stderr, "Cannot enter world directory %s\n"_fmt, dir);
                runflag = false;
                return 0;
            }
        }
        else if (arg == "--stop-file"_s && argv)
        {
            stop_file = argv.pop_front();
        }
        else if (arg == "--parent-pid"_s && argv)
        {
            parent_pid = atol(argv.pop_front().c_str());
        }
        else
        {
            FPRINTF(stderr, "Unknown argument: %s\n"_fmt, arg);
            runflag = false;
            return 0;
        }
    }

    // Each service reads its default conf/tmwa-*.conf from the world
    // directory when given no arguments of its own.
    ZString service_argv[] = {argv0};
    Slice<ZString> none(service_argv, 1);

    // Order matters: char registers with login, map registers with char.
    login::do_init(none);
    if (runflag)
        char_::do_init(none);
    if (runflag)
        map::do_init(none);

    if (runflag && (stop_file || parent_pid))
    {
        // A leftover stop file from an earlier session must not stop us.
        if (stop_file)
            remove(stop_file.c_str());
        Timer(gettick() + 1_s, check_host, 1_s).detach();
    }
    return 0;
}

static
void term_func(void)
{
    map::term_func();
    char_::term_func();
    login::term_func();
}
} // namespace aethyra
} // namespace tmwa

int main(int argc, char **argv)
{
    return tmwa_main(argc, argv, tmwa::aethyra::do_init, tmwa::aethyra::term_func);
}
