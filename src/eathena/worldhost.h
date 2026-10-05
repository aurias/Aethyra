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

#ifndef WORLDHOST_H
#define WORLDHOST_H

#include <string>

/**
 * Hosts a world on this computer by running the bundled aethyra-server.
 *
 * Worlds live in <home>/worlds/<name>. A new world is copied from the
 * server's world template and given its own internal password. The server
 * stops (and saves) when stop() is called or when the client exits, even
 * if the client crashes.
 *
 * The server and template are looked up next to the client executable
 * (server/aethyra-server[.exe] and server/world); the config options
 * "hostServerPath" and "hostWorldTemplate" override them.
 */
namespace WorldHost
{
    /** Port players connect to; the world template's login_port. */
    const short PORT = 6901;

    /**
     * Start hosting the named world, creating it first if needed.
     * Blocks until the server accepts connections. On failure returns
     * false and describes the problem in error.
     */
    bool start(const std::string &world, std::string &error);

    /** Whether this client started a server that is still running. */
    bool isRunning();

    /** Ask the server to save and stop, and wait for it to exit. */
    void stop();

    /** Directory holding the hosted worlds. */
    std::string worldsDir();
}

#endif
