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
// Usage: aethyra-server [--world DIR] [--help] [--version]
//
// All configuration and save paths are relative to the world directory
// (default: the current directory).

#include <unistd.h>

#include "../high/core.hpp"

#include "../io/cxxstdio.hpp"

#include "../char/char.hpp"
#include "../login/login.hpp"
#include "../map/map.hpp"

#include "../mmo/version.hpp"

#include "../poison.hpp"


namespace tmwa
{
namespace aethyra
{
static
int do_init(Slice<ZString> argv)
{
    ZString argv0 = argv.pop_front();
    while (argv)
    {
        ZString arg = argv.pop_front();
        if (arg == "--help"_s)
        {
            PRINTF("Usage: %s [--world DIR] [--help] [--version]\n"_fmt, argv0);
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
            if (chdir(dir.c_str()) != 0)
            {
                FPRINTF(stderr, "Cannot enter world directory %s\n"_fmt, dir);
                runflag = false;
                return 0;
            }
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
