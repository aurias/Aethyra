/*
 *  Aethyra
 *
 *  This file is part of Aethyra.
 *
 *  Aethyra is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  any later version.
 *
 *  Aethyra is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Aethyra; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include <filesystem>
#include <fstream>
#include <random>
#include <sstream>

#include <physfs.h>
#include <SDL.h>
#include <SDL_net.h>

#ifdef WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "worldhost.h"

#include "../engine.h"

#include "../core/configuration.h"
#include "../core/log.h"

#include "../core/utils/gettext.h"
#include "../core/utils/stringutils.h"

namespace fs = std::filesystem;

namespace
{
    /** Placeholder password the world template ships with. */
    const std::string TEMPLATE_PASSWORD = "change-me-char";

    /** Seconds to wait for the server to start or to stop. */
    const int START_TIMEOUT = 20;
    const int STOP_TIMEOUT = 15;

#ifdef WIN32
    PROCESS_INFORMATION server = { 0, 0, 0, 0 };
    const char *SERVER_NAME = "aethyra-server.exe";
#else
    pid_t server = 0;
    const char *SERVER_NAME = "aethyra-server";
#endif
    std::string stopFile;

    std::string baseDir()
    {
        const char *dir = PHYSFS_getBaseDir();
        return dir ? dir : "";
    }

    std::string serverPath()
    {
        return config.getValue("hostServerPath",
                               baseDir() + "server/" + SERVER_NAME);
    }

    std::string templatePath()
    {
        return config.getValue("hostWorldTemplate", baseDir() + "server/world");
    }

    std::string randomPassword()
    {
        static const char chars[] = "abcdefghijkmnopqrstuvwxyz23456789";
        std::random_device random;
        std::string password;
        for (int i = 0; i < 20; i++)
            password += chars[random() % (sizeof(chars) - 1)];
        return password;
    }

    bool readFile(const fs::path &path, std::string &contents)
    {
        std::ifstream in(path, std::ios::binary);
        if (!in)
            return false;
        std::ostringstream buffer;
        buffer << in.rdbuf();
        contents = buffer.str();
        return true;
    }

    bool writeFile(const fs::path &path, const std::string &contents)
    {
        std::ofstream out(path, std::ios::binary | std::ios::trunc);
        out << contents;
        return out.good();
    }

    /**
     * Copy the world template and give the copy its own credentials. The
     * internal password only links the services over loopback, but every
     * world still gets a fresh one, and the template's test account is
     * left out.
     */
    bool createWorld(const fs::path &dir, std::string &error)
    {
        const fs::path source = templatePath();
        if (!fs::exists(source / "conf"))
        {
            error = strprintf(_("World template not found at %s"),
                              source.string().c_str());
            return false;
        }

        std::error_code ec;
        fs::create_directories(dir.parent_path(), ec);
        fs::copy(source, dir, fs::copy_options::recursive, ec);
        if (ec)
        {
            error = strprintf(_("Could not create world: %s"),
                              ec.message().c_str());
            return false;
        }

        const std::string password = randomPassword();
        const char *confs[] = { "conf/login.conf", "conf/char.conf",
                                "conf/map.conf" };
        for (const char *name : confs)
        {
            std::string text;
            if (!readFile(dir / name, text))
            {
                error = strprintf(_("World template is missing %s"), name);
                return false;
            }
            std::string::size_type pos;
            while ((pos = text.find(TEMPLATE_PASSWORD)) != std::string::npos)
                text.replace(pos, TEMPLATE_PASSWORD.size(), password);
            writeFile(dir / name, text);
        }

        // No accounts: players register themselves. (The services' own
        // link is authenticated by the conf files above, not this file.)
        writeFile(dir / "save" / "account.txt", "%newid%\t2000000\n");

        logger->log("WorldHost: created world in %s", dir.string().c_str());
        return true;
    }

    bool launch(const fs::path &world, std::string &error)
    {
        const std::string exe = serverPath();
        if (!fs::exists(exe))
        {
            error = strprintf(_("World server not found at %s"), exe.c_str());
            return false;
        }

        fs::create_directories(world / "log");
        const std::string logFile = (world / "log" / "server.out").string();
        stopFile = (world / "server.stop").string();

#ifdef WIN32
        std::string commandLine = "\"" + exe + "\" --world \"" +
            world.string() + "\" --stop-file \"" + stopFile +
            "\" --parent-pid " + toString(GetCurrentProcessId());

        SECURITY_ATTRIBUTES inherit = { sizeof(inherit), NULL, TRUE };
        HANDLE log = CreateFileA(logFile.c_str(), GENERIC_WRITE,
                                 FILE_SHARE_READ, &inherit, CREATE_ALWAYS,
                                 FILE_ATTRIBUTE_NORMAL, NULL);

        STARTUPINFOA startup;
        ZeroMemory(&startup, sizeof(startup));
        startup.cb = sizeof(startup);
        if (log != INVALID_HANDLE_VALUE)
        {
            startup.dwFlags = STARTF_USESTDHANDLES;
            startup.hStdOutput = log;
            startup.hStdError = log;
            startup.hStdInput = NULL;
        }

        std::vector<char> mutableCommand(commandLine.begin(),
                                         commandLine.end());
        mutableCommand.push_back('\0');
        BOOL ok = CreateProcessA(exe.c_str(), &mutableCommand[0], NULL, NULL,
                                 TRUE, CREATE_NO_WINDOW, NULL,
                                 world.string().c_str(), &startup, &server);
        if (log != INVALID_HANDLE_VALUE)
            CloseHandle(log);
        if (!ok)
        {
            error = strprintf(_("Could not start the world server (error %lu)"),
                              GetLastError());
            ZeroMemory(&server, sizeof(server));
            return false;
        }
#else
        const std::string parent = toString(getpid());
        const std::string worldDir = world.string();
        pid_t child = fork();
        if (child == -1)
        {
            error = _("Could not start the world server");
            return false;
        }
        if (child == 0)
        {
            int log = open(logFile.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (log != -1)
            {
                dup2(log, 1);
                dup2(log, 2);
                close(log);
            }
            execl(exe.c_str(), exe.c_str(), "--world", worldDir.c_str(),
                  "--stop-file", stopFile.c_str(), "--parent-pid",
                  parent.c_str(), (char*) NULL);
            _exit(127);
        }
        server = child;
#endif
        logger->log("WorldHost: started %s for %s", exe.c_str(),
                    world.string().c_str());
        return true;
    }

    /** Wait until the server accepts connections or exits. */
    bool waitUntilReady(std::string &error, const fs::path &world)
    {
        IPaddress address;
        SDLNet_ResolveHost(&address, "127.0.0.1", WorldHost::PORT);
        for (int i = 0; i < START_TIMEOUT * 5; i++)
        {
            if (!WorldHost::isRunning())
            {
                error = strprintf(_("The world server stopped. See %s"),
                    (world / "log" / "server.out").string().c_str());
                return false;
            }
            if (TCPsocket socket = SDLNet_TCP_Open(&address))
            {
                SDLNet_TCP_Close(socket);
                return true;
            }
            SDL_Delay(200);
        }
        error = _("The world server did not start in time.");
        return false;
    }
}

std::string WorldHost::worldsDir()
{
    return engine->getHomeDir() + "/worlds";
}

bool WorldHost::start(const std::string &name, std::string &error)
{
    if (isRunning())
        return true;

    const fs::path world = fs::path(worldsDir()) / name;
    if (!fs::exists(world / "conf") && !createWorld(world, error))
        return false;

    if (!launch(world, error))
        return false;

    if (!waitUntilReady(error, world))
    {
        stop();
        return false;
    }
    return true;
}

bool WorldHost::isRunning()
{
#ifdef WIN32
    return server.hProcess &&
           WaitForSingleObject(server.hProcess, 0) == WAIT_TIMEOUT;
#else
    if (server <= 0)
        return false;
    if (waitpid(server, NULL, WNOHANG) == 0)
        return true;
    server = 0;
    return false;
#endif
}

void WorldHost::stop()
{
    if (!isRunning())
        return;

    logger->log("WorldHost: stopping the world server");
    // The server polls for this file once a second, then saves and exits.
    writeFile(stopFile, "stop\n");

    for (int i = 0; i < STOP_TIMEOUT * 10 && isRunning(); i++)
        SDL_Delay(100);

    if (isRunning())
    {
        logger->log("WorldHost: server did not stop; terminating it");
#ifdef WIN32
        TerminateProcess(server.hProcess, 1);
#else
        kill(server, SIGKILL);
        waitpid(server, NULL, 0);
        server = 0;
#endif
    }

#ifdef WIN32
    if (server.hProcess)
    {
        CloseHandle(server.hProcess);
        CloseHandle(server.hThread);
        ZeroMemory(&server, sizeof(server));
    }
#endif
}
