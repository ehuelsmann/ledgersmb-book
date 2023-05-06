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
use Time::Piece;

use diagnostics;
use Data::Dumper qw(Dumper); 

use Selenium::Firefox;
# use Selenium::Screenshot; # For comparing images
# use YAML::PP;

use DBI;

use feature 'signatures';
no warnings "experimental::signatures";

print "Example Usage:\n";
print "  PGHOSTADDR='172.16.1.218' PGPORT='5001' PGDATABASE='jack' PGUSER='postgres' PGPASSWORD='abc' \\\n";
print "  LSMB_ADMIN_USERNAME='neil' LSMB_ADMIN_PASSWORD='asdfghjkl' LSMB_BASE_URL='http://vmwareledgerdev.local:5000' perl get-screen-shots.pl\n";

# Configuration
my $user_name     = $ENV{'LSMB_ADMIN_USERNAME'}; # The LedgerSMB user to login as
my $user_password = $ENV{'LSMB_ADMIN_PASSWORD'}; # The LedgerSMB user's password
my $company       = $ENV{'PGDATABASE'};          # The LedgerSMB company to log into
my $base_url      = $ENV{'LSMB_BASE_URL'};       # The LedgerSMB server base URL
my $screen_shot_base_path = '../auto-screenshots';
my $capture_delay = 1; # delay after loading URL and before screenshot in seconds

# Access the database and retrieve the menu items with URLs and
# a synthesized screenshot file name.
sub get_menu_structure($conn) {
	my $sql = <<'SQL';
            WITH RECURSIVE file_names (id, label, parent, url, screen_file_name) AS (
                    SELECT 	id,
                            label,
                            parent,
                            replace('erp.pl?action=root#/' || url, '//', '/') AS url, -- import URLs have leading /
                            replace(lower(label || '.png'), ' ', '-') AS screen_file_name
                    FROM 	menu_node
                    WHERE 	url IS NOT NULL
                UNION
                    SELECT  mn.id, 
                            fn.label,
                            mn.parent, 
                            fn.url,
                            replace(lower(mn.label), ' ', '-') || '--' || fn.screen_file_name AS screen_file_name
                    FROM 	menu_node AS mn, 
                            file_names AS fn
                    WHERE 	mn.id = fn.parent
            )
            SELECT 	label, 
                    url,
    				replace(screen_file_name, 'top-level--', '') AS screen_file_name -- Remove unnecessary top level.
			FROM 	file_names
            WHERE 	screen_file_name ilike 'top-level--%'  -- Only need the top level not the recurrsive intermediates.
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
sub login($driver)  {
    if (!defined $user_name) { die "LSMB user name missing" };
    if (!defined $user_password) { die "LSMB password missing" };
    if (!defined $company) { die "LSMB company name missing" };

    # Fill User Name
    my $name_element = $driver->find_element_by_xpath("//input[\@name='username']");
    if (!defined $name_element) { die "Name xpath element not defined"; }
    $name_element->send_keys($user_name);

    # Fill Password
    my $password_element = $driver->find_element_by_xpath("//input[\@name='password']");
    if (!defined $password_element) { die "Password xpath element not defined"; }
    $password_element->send_keys($user_password);

    # Fill Company
    my $company_element = $driver->find_element_by_xpath("//input[\@name='company']");
    if (!defined $company_element) { die "Company xpath element not defined"; }
    $company_element->send_keys($company);

    # Click Login Button
    my $login_button_element = $driver->find_element_by_xpath("//lsmb-button[\@id='login']");
    if (!defined $login_button_element) { die "Login button xpath element not defined"; }
    $login_button_element->click();
}

# If an error dialog is visible, close it.
sub close_error ($driver, $screen_file_name) {
    eval {
        my $error_element = $driver->find_element_by_xpath("//div[\@id='errorDialog']/*/span[\@role='button']");
        if (defined $error_element) {
            $driver->mouse_move_to_location(element => $error_element);
            $driver->click();
        }
    };
    my $an_error = $@; 
    if ($an_error) {
        if ( index($an_error, 'Origin element is not displayed at') == -1) {
            # Print the error if the error is not the expected error where the dialog is not presented.
            print "\n$an_error\n";
            # On error no need to wait.
        }
    }
    else {
        print "  Dismissing Error dialog.\n";
        sleep($capture_delay);      # Wait for dialog to dismiss.
    }
}

# Attempt to select the password tab in the preferences menu view.
sub select_preferences_tab ($driver) {
    # https://github.com/ledgersmb/LedgerSMB/blob/f3db4354d9cc8e2f98288ecd687f20a5b44a1b36/xt/lib/Pherkin/Extension/pageobject_steps/nav_steps.pl#L177
    my $preference_tab_element = $driver->find_element_by_xpath(".//*[\@role='tab' and text()='Preferences']");
    if (!defined $preference_tab_element) { die "Preferences xpath element not defined"; }
    $preference_tab_element->click();
}

sub open_database() {
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
            AutoCommit => 1,
            # ReadOnly => 0,
            PrintError => 1,
            RaiseError =>  1 })
        or die "Unable to connect: $DBI::errstr\n";

    print "Connected to the '$dbh->{pg_db}' database.\n";
    if ($dbh->{pg_db} eq 'postgres') {
        die "This code must connect to an LSMB company database, not the postgres database.\n";
    }
    return $dbh;
}

# A dummy pre-process subroutine for testing
sub preprocess_dummy($driver) { print "  Pre Processing Example\n"; }

# A dummy post-process subroutine for testing
sub postprocess_dummy($driver) { print "  Post Processing Example\n"; }

# For troubleshooting, this subroutine can be used in either the pre or post processing.
sub wait_for_keyboard($driver) {
    # For troubleshooting, pause the see the last screen.
    print "Press Enter to continue: ";
    <>;
}

# Contains processing data for each screenshot that needs non-default processing.
# If the file name is not found as a hash key, then the 'default' hash entry will be used.
# h = resize the view to this height prior to the screenshot
# w = resize the view to this width prior to the screen shot
# pre = subroutine to run after loading the view, but prior to the screenshot
# post = subroutine to run after the screen shot
# Example:
#    'login.png' => { h => 520, w => 520,  pre => \&preprocess_dummy, post => \&postprocess_dummy},
my %processing_config = (
    'example'     => { h => 520, w => 520,  pre => \&preprocess_dummy, post => \&postprocess_dummy},  # Example should not be used.
    'default'     => { h => 820, w => 1200},  # The default view resize values if there is no match file name match
    'login.png'   => { h => 520, w => 520},   # No need for a lot of empty space
    'welcome.png' => { h => 700, w => 1280, pre => \&login},  # Make the view wider since it includes the welcome text
    'preferences-preferences.png' => {h => 820, w => 1200, pre => \&select_preferences_tab},
    # 'preferences-password.png' => {h => 820, w => 1200, post => \&wait_for_keyboard},
);

# If the resize value is different than the current view dimensions
# then resize the view.
sub check_and_resize($driver, $to_height, $to_width) {
    my $window_size = $driver->get_window_size();
    if ($window_size->{'height'} == $to_height && $window_size->{'width'} == $to_width) {
        return; # No change needed
    }
    print "  Set view to: $to_height, $to_width\n";
    $driver->set_window_size($to_height, $to_width);
    sleep(0.1); # May not need this, but should verify before removing.
}

# Process a screenshot
sub process_screen($driver, $url, $screen_file_name, $check_error_dialog=1) {
    print "Processing: $screen_file_name\n";

    # If the URL is not supplied, then proceed without any navigation. 
    # The screen may have been updated by some previous action.
    if (defined $url) {
        # Navigate to the screen
        $driver->get("$base_url/$url");
        sleep($capture_delay);          # Wait for screen to load
    }

    # If error dialog is showing, close it.
    if ($check_error_dialog) {
        close_error($driver, $screen_file_name);
    }

    # Get the configuration, either specific to the screen file name or the default.
    my %config = (exists $processing_config{$screen_file_name}) ? $processing_config{$screen_file_name}->%* : $processing_config{default}->%* ;

    # Resize if necessary
    check_and_resize($driver, $config{h}, $config{w} );

    # If defined do pre processing, such as loading data specific to this screen.
    if (defined $config{pre}) {
        $config{pre}($driver);
    }

    # Capture the screenshot
    my $main_div = $driver->find_element_by_xpath("//*[\@id='maindiv']"); # ignore menu in screenshot
    $main_div->capture_screenshot("$screen_shot_base_path/$screen_file_name");

    # If defined, do post processing.
    if (defined $config{post}) {
        $config{post}($driver);
    }

}

#-------------
# Main
#-------------

# Open a database connection
my $dbh = open_database();

# Make the toaster go away for these tests by disabling it in the database
disable_toster($dbh);

# Set up Firefox Selenium driver
my $firefox_driver = Selenium::Firefox->new;
# $firefox_driver->debug_on;

# Get the menu structure from the database
my $menu_structure_data = get_menu_structure($dbh);

# Grab a screenshot of the LSMB login screen.
process_screen($firefox_driver, "login.pl", "login.png", 0);

# Grab a screenshot of the welcome screen after login
process_screen($firefox_driver, undef, 'welcome.png', 0);

my $logout_ref; # Create cache for logout, because its screenshot needs to be done last.

# Iterate through all of the menu items and save screen grabs
while (my $ref = $menu_structure_data->fetchrow_hashref('NAME_lc') ) {
    if (!exists $ref->{url})              { die "Unable to find menu url."; }
    if (!exists $ref->{screen_file_name}) { die "Unable to find screen file name."; }
    if (!exists $ref->{label})            { die "Unable to find menu label."; }

    if ($ref->{label} eq 'Logout') {
        $logout_ref = $ref;
        next;   # Skip logout until last otherwise the rest of the screenshots will fail
    }

    if ($ref->{label} eq 'Preferences') {
        # Preferences contains 2 tabs so we have to distinguish between them.
        # First the default tab - Password
        process_screen($firefox_driver, $ref->{url}, 'preferences-password.png');
        # Then the actual preferences tab. The navigation code is in the preprocessing subroutine.
        process_screen($firefox_driver, undef, 'preferences-preferences.png');
    }
    else {
        process_screen($firefox_driver, $ref->{url}, $ref->{screen_file_name});
    }
    # have to process tabs for general-journal--year-end.png
    # have to process tabs for contacts person company
}

# Process the logout screenshot as the last item
process_screen($firefox_driver, $logout_ref->{url}, $logout_ref->{screen_file_name} );

# For troubleshooting, pause the see the last screen.
# print "Press Enter to continue: ";
# <>;

# Done, clean up
enable_toaster($dbh);
$firefox_driver->shutdown_binary;
$menu_structure_data->finish();
$dbh->disconnect();

# Misc Notes
# https://github.com/ledgersmb/LedgerSMB/blob/c799718433e18f6ffce6e2eda1cd15df178b6999/xt/lib/PageObject/App/Login.pm#L35
# https://github.com/perl-weasel/weasel/blob/58aea10134b46bf10b1e8f97c595abe53ac6a801/lib/Weasel/FindExpanders/HTML.pm#L130
