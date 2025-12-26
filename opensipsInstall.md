# Step 1: Add the OpenSIPS APT Repository 
OpenSIPS modules are often not in the default Ubuntu repositories or are outdated. The official OpenSIPS APT Repository provides current packages. For Ubuntu 22.04 (Jammy Jellyfish), you can add the repository for the desired OpenSIPS version (e.g., 3.6 stable LTS) by running: 
bash
sudo add-apt-repository ppa:opensips/3.6 -y
sudo apt update
Note: Replace 3.6 with another supported version if necessary.

# Step 2: Install Required Packages 
The opensips-sqlite-module package provides the necessary OpenSIPS integration, and libsqlite3-dev provides the external development libraries required for the module to function correctly. 
bash
sudo apt install opensips opensips-sqlite-module libsqlite3-dev -y

# Step 3: Verify and Configure
Verify installation:
bash
opensips -V
opensips -m | grep sqlite
Configure OpenSIPS: You will need to edit your OpenSIPS configuration file (typically /etc/opensips/opensips.cfg) to load the db_sqlite module and configure your database URL.Add lines similar to these in your opensips.cfg:
opensips.cfg
loadmodule "db_sqlite.so"

# Example database URL (adjust path as needed)
modparam("usrloc", "db_url", "sqlite:///var/run/opensips/opensips.db")
Create the database (if needed): You can use opensips-cli to create and manage the database schema.First, ensure opensips-cli is configured with the correct database_url in /etc/opensips/opensips-cli.cfg or ~/.opensips-cli.cfg, then run:
bash
sudo opensips-cli -x database create