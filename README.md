## OHD Admin Wrapper

### About

OHD Admin Wrapper (OHDAW) is a set of tools designed to ease the burden of hosting one or more servers for the `Drakeling Labs` video game [Operation: Harsh Doorstop](https://store.steampowered.com/app/736590/Operation_Harsh_Doorstop/). It is comprised of a Ruby webserver (Sinatra) and associated tools which provide an easy-to-use browser front-end for configuring and managing a server on either Linux or Windows.

It can also be used to remotely monitor and administer servers via RCON.

### Screenshots

TO DO

### Features

An easy-to-use webserver with configurable parameters via TOML file (and web interface):
  - Bind IP/Port
  - SSL Enabled
  - Verify SSL Enabled
  - Cert/Key Paths
  - Session secret

Local server features:
- **Server Setup page**
  - Guides you through installing SteamCMD manually
  - Detects SteamCMD installation and server installation
  - Shows available server update
  - Provides a simple interface to install and manually update/verify the server files as well as enable automatic update
  - SteamCMD log (see known issue below for Windows)
- **Server Config page**
  - Supports multiple server configurations
  - Easy-to-use configuration options for your servers
  - Blurring/redaction of sensitive information
  - Dropdowns for enumerated settings
  - Editable config files (Paste your current settings here! Matching settings above will override what was entered.)
    - `Game.ini`
    - `Engine.ini`
    - `Admins.cfg`
    - `MapCycle.cfg`
    - `Bans.cfg`
    - Local copies of these files are stored in `ohd-admin-wrapper/server-config`. Before launching the server, the manual config is applied to the `server-config` files, then those files are copied into the appropriate places in order for the server to use them. This prevents the server from overwriting our changes.
- **Server Control page**
  - Select from saved configs or running servers
  - Server status
  - Start/Restart/Stop buttons
  - Detailed PID and process exit toasts
  - Thread, player, and bot counts
  - Player list (with kick/ban buttons and editable reason)
  - Chat log with chat input (RCON say)
  - RCON log with RCON input
  - Server log with download options
- **Server Status page**
  - List of all running servers with their metadata and players

Extra tools:
- **Remote Monitor Tool**
  - Allows monitoring and administration of servers when provided with valid IP, Query Port, RCON Port, and RCON Password
  - Shows server, query, and RCON status, player list with admin functionality, and RCON console.
  - Can spawn multiple server monitors and switch between them at will
  - Can save configurations for easy monitoring later
  - If a third party hosts your server(s) for you, this is probably what you're looking for
- **RCON Tool**
  - Allows remote RCON commands (with the given IP, port, and password).
- **SteamCMD Tool**
  - This tool allows passthrough to the SteamCMD installation. This could be useful for installing/updating other games, etc.

Wrapper webserver features:
- **Config page**
  - Easy configuration for all webserver parameters
  - Button to download OHDAW logs
  - Button to update OHDAW to the latest version (restart required)
  - Button to restart the webserver (to apply changes)
- **Users page**
  - Easy addition/modification of users to allow access to server admin features.
  - Protections to prevent removing the last Host (and therefore losing access to webserver self-configuration and user configuration)
  - User roles:
    - `Host`: Server host; can configure webserver, users, and everything else
    - `Admin`: Server admin; can do everything except configure the webserver and users
    - `Moderator`: Server moderator; can kick and ban users via the status page
    - `User`: Read-only role which can access basic account features and the server status page
  - New users have a random password automatically generated; this (along with the user name) is given to the user by the host. Upon first login, users are asked to change their password. This helps keep passwords private.
- **Log page**
  - Shows live user authentication and incoming request information

User features:
- **Change password**
- **Log out**

Command-line parameters:
- CLI parameters are passed from the start script (`linux_start.sh`/`windows_start.bat`) to `admin-interface/lib/webapp.rb`
- OHDAW supports the following command-line parameter(s)
  - `--start/-s [server_config_name_or_id]`
    - Example: `-s 'My Server 1' -s 'My Server 2' -s 'ebfc1f5a-ee68-45ab-9248-6f425f6d587d'`
    - Start one or more servers automatically with the named configuration (matched based on `Config Name` or `Config ID`). This can be used in combination with system startup scripts (e.g. systemd unit example in `extras/systemd`) or Windows Task Scheduler to run your server(s) on boot.
  - `--log-level/-l [log_level]`
    - Example: `-l debug`
    - Sets the log level. Only messages at or above the set level are printed to STDOUT; all logs are still written to `admin-interface/log/ohd-admin-wrapper.log`. One of: `debug`, `info`, `warn`, `error`, `fatal`

### Prerequisites

- Windows (11 tested) or Linux (Debian 11 tested)
- A Ruby `3.1.2`+ (check with `ruby -v`) installation with the Bundler gem (`gem install bundler`). I recommend [rbenv](https://github.com/rbenv/rbenv) to manage Ruby installations on Linux and [RubyInstaller for Windows](https://rubyinstaller.org/downloads/) to install Ruby on Windows.
- If using this tool to run a server, grab a portable version of [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD#Downloading_SteamCMD) (we'll extract it to `ohd-admin-wrapper/steamcmd/installation`)
  - [Windows SteamCMD](https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip)
  - [Linux SteamCMD](https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz)
- Other OHD-specific prerequisites may be required, e.g. `apt install lib32gcc-s1` on Debian 11

### Installation

- Download and extract (or clone) the repository
- If you plan to install/run a server, [install SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD#Downloading_SteamCMD) manually to `ohd-admin-wrapper/steamcmd/installation`. `steamcmd.exe`/`steamcmd.sh` should be in the `installation` directory.
  - During runtime, we change the wrapper's `HOME` environment variable to `ohd-admin-wrapper/steamcmd` in order to contain SteamCMD's home directory pollution (on Linux) within the wrapper. You may see shell or Steam-related files in this directory as a result.

[Docker instructions](/Docker.md) are also available.

### Starting the Admin Wrapper

- Run the start script for your OS (`windows_start.bat` for Windows, `linux_start.sh` for Linux (BASH))
- Navigate to the web interface in your browser (e.g. https://localhost:51422/)
- Log in with the default admin credentials (`admin`/`password`). You will be prompted to set a new password for the `admin` account. If you ever forget this password, just delete `admin-interface/config/users.json` and restart the webserver to regenerate the default `admin`/`password` account.
- If running a server
  - Follow the instructions on the `Server -> Setup` to install the OHD server (refresh may be required to show installed status)
  - Configure the server via the `Server -> Config` page
  - Run the server via the `Server -> Control` page
- If administrating remote server(s)
  - Use the `Tools -> Monitor` page

### Known issues

These are the currently known issues. If you can fix any of these or know what to do, please send a pull request or [create a detailed GitHub issue](https://github.com/Joe-Klauza/ohd-admin-wrapper/issues/new). Thanks!

- SteamCMD output on Windows takes forever!
  - SteamCMD buffers progress output when it doesn't detect an interactive session (i.e. when it's being run by ohd-admin-wrapper). This output doesn't become available until the update/validation completes. There is a workaround we're using for Linux (PTY) to emulate an interactive session, but such a workaround does not appear to be feasible on Windows at this time. [(more info here)](https://github.com/ValveSoftware/Source-1-Games/issues/1684)

### Donate

If you'd like to show your appreciation of `OHD Admin Wrapper`, please [donate via PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=QZDY3PPUMH5TU&item_name=OHD%20Admin%20Wrapper&currency_code=USD) (or suggest other methods).  
[![](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=QZDY3PPUMH5TU&item_name=OHD%20Admin%20Wrapper&currency_code=USD)
