#!/usr/bin/perl

# get-screen-shots.pl
#
# Query a live LSMB instance and save necessary screen grabs to PNG files.
# Does not add meta data to the images because they would change each time.
#
# The menu derived screen shot file name format is <parent label>--<label> 
# all lowercased and spaces replaced with hyphens ('-').
#

use warnings;
use strict;
use diagnostics;
use Time::Piece;

use Selenium::Firefox;

# use Selenium::Screenshot; # For comparing images

use DBI;

use feature 'signatures';
no warnings "experimental::signatures";

# Configuration
my $user_name = 'neil';
my $user_password = 'asdfghjkl';
my $base_url = 'http://vmwareledgerdev.local:5000';
my $screen_shot_base_path = '../auto-screen-shots';
my $capture_delay = 1; # seconds

# Access the database and retreive the menu items with URLs and
# a synthesized screenshot file name.
sub get_menu_structure($conn) {
	my $sql = <<'SQL';
           WITH RECURSIVE file_names (id, label, parent, url, position, screen_file_name) AS (
                    SELECT 	id,
                            label,
                            parent,
                            replace('erp.pl?action=root#/' || url, '//', '/') AS url, -- import URLs have leading /
                            position,
                            replace(lower(label || '.png'), ' ', '-') AS screen_file_name
                    FROM 	menu_node
                    WHERE 	url IS NOT NULL
                
                UNION
                    SELECT  mn.id, 
                            fn.label,
                            mn.parent, 
                            fn.url,
                            fn.position,
                            replace(lower(mn.label), ' ', '-') || '__' || fn.screen_file_name AS screen_file_name
                    FROM 	menu_node AS mn, 
                            file_names AS fn
                    WHERE 	mn.id = fn.parent
            )
            SELECT 	label, 
                    url,
    				replace(screen_file_name, 'top-level__', '') AS screen_file_name -- Remove unnecessary top level.
			FROM 	file_names
            WHERE 	screen_file_name ilike 'top-level\_\_%'  -- Only need the top level not the recurrsive intermediates.
            ORDER BY screen_file_name
SQL
    my $sth = $conn->prepare($sql);
    $sth -> execute();
    return $sth
}

sub disable_toster ($conn) {
    	my $sql = <<'SQL';
        INSERT INTO defaults (setting_key, value) VALUES ('__disableToaster', 'yes')
        ON CONFLICT DO NOTHING;
SQL
    $conn->do($sql);
}

sub enable_toaster ($conn) {
    	my $sql = <<'SQL';
        DELETE FROM defaults 
        WHERE setting_key = '__disableToaster';
SQL
    $conn->do($sql);
}

# Capture login screen shot, then log the given user into LSMB
sub login($driver, $user_name, $password, $company) {
    $driver->get("$base_url/login.pl");
    $driver->capture_screenshot("$screen_shot_base_path/login.png");

    # Fill User Name
    my $name_element = $driver->find_element_by_xpath("//input[\@name='username']");
    if (!defined $name_element) {
        die "Name xpath element not defined";
    }
    $name_element->send_keys($user_name);

    # Fill Password
    my $password_element = $driver->find_element_by_xpath("//input[\@name='password']");
    if (!defined $name_element) {
        die "Password xpath element not defined";
    }
    $password_element->send_keys($password);

    # Fill Company
    my $company_element = $driver->find_element_by_xpath("//input[\@name='company']");
    if (!defined $company_element) {
        die "Company xpath element not defined";
    }
    $company_element->send_keys($company);

    # Click Login Button
    my $login_button_element = $driver->find_element_by_xpath("//lsmb-button[\@id='login']");
    if (!defined $login_button_element) {
        die "Login button xpath element not defined";
    }
    $login_button_element->click();
}

# Check of an error window is visible and close it.
sub close_error ($driver) {
    # my $error_element = $driver->find_element_by_xpath("//span[\@class='closeText']");
    my $error_element = $driver->find_element_by_xpath(".//span[\@class='dijitDialogCloseIcon']");
    if (defined $error_element) {
        #$error_element->cancel();
        $error_element->click();
    }
}

sub logout () {
    # http://vmwareledgerdev.local:5000/erp.pl?action=root#/login.pl?action=logout&target=_top#1683062483134
}

#-------------
# Main
#-------------
print "Example Usage:\n";
print "  PGHOSTADDR='172.16.1.218' PGPORT='5001' PGDATABASE='jack' PGUSER='postgres' PGPASSWORD='abc' perl get-screen-shots.pl\n";

# use environment variables for authentication
# host         PGHOST                  local domain socket
# hostaddr     PGHOSTADDR              local domain socket
# port         PGPORT                  5432
# dbname*      PGDATABASE              current userid
# username     PGUSER                  current userid
# password     PGPASSWORD              (none)
# options      PGOPTIONS               (none)
# service      PGSERVICE               (none)
# sslmode      PGSSLMODE               (none)
my $dbh = DBI->connect('dbi:Pg:', undef, undef, {
        AutoCommit => 0,
        ReadOnly => 0,
        PrintError => 1,
        RaiseError =>  1 })
    or die "Unable to connect: $DBI::errstr\n";

print "Connected to the '$dbh->{pg_db}' database.\n";
if ($dbh->{pg_db} eq 'postgres') {
    die "This code must connect to an LSMB company database, not the postgres database.\n";
}

# Make the toaster go away for these tests.
disable_toster($dbh);

# Set up Firefox
my $firefox_driver = Selenium::Firefox->new;

# Get the menu structure
my $menu_structure_data = get_menu_structure($dbh);

# Login to LSMB
$firefox_driver->set_window_size(480, 640);
login($firefox_driver, $user_name, $user_password, $dbh->{pg_db});

# Capture the main view after login
sleep($capture_delay); # Wait for menu to load.
$firefox_driver->set_window_size(820, 1200); # Make the view larger
$firefox_driver->capture_screenshot("$screen_shot_base_path/main.png");

# Iterate through all of the menu items and save screen grabs
my $logout_ref; # Cache logout and do it last.
while (my $ref = $menu_structure_data->fetchrow_hashref('NAME_lc') ) {
    if (!defined $ref->{url}) { die "Unable to find menu url."; }
    if (!defined $ref->{screen_file_name}) { die "Unable to find screen file name."; }
    if (!defined $ref->{label}) { die "Unable to find menu label."; }

    if ($ref->{label} eq 'Logout') {
        $logout_ref = $ref;
        next;   # Skip logout for now because that causes the rest of the screenshots to fail
    }

    $firefox_driver->get("$base_url/$ref->{url}");
    sleep($capture_delay);          # Wait for menu to load

    eval {
        close_error($firefox_driver);   # Check if error dialog and if so, close it.
    };
    print $@;
    
    my $main_div = $firefox_driver->find_element_by_xpath("//*[\@id='maindiv']"); # ignore menu in screenshot
    $main_div->capture_screenshot("$screen_shot_base_path/$ref->{screen_file_name}");

    if ( $ref->{screen_file_name} eq 'shipping__transfer.png') {
    # For troubleshooting, pause the see the last screen.
    print "Press Enter to continue $ref->{screen_file_name}: ";
    <>;
    }
}

# Save screenshot the logout menu as the last item
$firefox_driver->get("$base_url/$logout_ref->{url}");
sleep($capture_delay); # Wait for menu to load.
$firefox_driver->capture_screenshot("$screen_shot_base_path/$logout_ref->{screen_file_name}");

# For troubleshooting, pause the see the last screen.
print "Press Enter to continue: ";
<>;

# Done, clean up
enable_toaster($dbh);
$firefox_driver->shutdown_binary;
$menu_structure_data->finish();
$dbh->disconnect();

# Misc Notes
# https://github.com/ledgersmb/LedgerSMB/blob/c799718433e18f6ffce6e2eda1cd15df178b6999/xt/lib/PageObject/App/Login.pm#L35
# https://github.com/perl-weasel/weasel/blob/58aea10134b46bf10b1e8f97c595abe53ac6a801/lib/Weasel/FindExpanders/HTML.pm#L130
