#!/usr/bin/perl

# get-screen-shots.pl
#
# Query a live LSMB instance and save screenshots to PNG files.
# Does not add meta data to the images because they would change each time.
#
# A small subset of the screens have default dates that will change each different
# day the screens are grabbed.  
#
# The menu derived screen shot file name format is
#   <parent label>--<parent label>--<label> 
# all lowercased with spaces replaced with hyphens ('-').
#
# The screenshots use the data expected in the book's prose.  That means
#   the user is 'admin' and the company name is 'example_inc'.
# 

use warnings;
use strict;
use Time::Piece;

# use Data::Dumper;
# use Diagnostics;

use Getopt::Long;
# use Pod::Usage; # TODO convert print statements to real pod help

use Selenium::Firefox;
use Selenium::Remote::Driver;
use Selenium::Firefox::Profile;
use DBI;

use feature 'signatures';
no warnings "experimental::signatures";

# -----------------
# Configuration
# -----------------
my $user_name     = $ENV{'LSMB_ADMIN_USERNAME'}; # The LedgerSMB user to login as
my $user_password = $ENV{'LSMB_ADMIN_PASSWORD'}; # The LedgerSMB user's password
my $company       = $ENV{'PGDATABASE'};          # The LedgerSMB company to log into
my $base_url      = $ENV{'LSMB_BASE_URL'};       # The LedgerSMB server base URL
my $screen_shot_base_path = '../auto-screenshots';
my $capture_delay = 1; # delay after loading URL and before screenshot in seconds
my $login_screenshot_file_name = 'login.png';
my $welcome_screenshot_file_name = 'welcome.png';
# Set up Firefox profile
my $profile = Selenium::Firefox::Profile->new; # Clear everything out after the test ends.
$profile->set_boolean_preference(
    'browser.cache.disk.enable' => 0,
    'browser.cache.memory.enable' => 1,
    'browser.cache.offline.enable' => 0,
    'network.http.use-cache' => 0
); 

# -----------------
# Option processing
# -----------------
my $do_login = 0;
my $do_setup = 0;
my $do_help = 0;
my $do_debug = 0;
GetOptions(
    'login!' => \$do_login,
    'setup!' => \$do_setup,
    'help' => \$do_help,
    'debug' => \$do_debug,
);
if (($do_help) || (!$do_login && !$do_setup)) {
    print_help();
    exit 0;
}
# Make sure to do the following after Getopt processing because that processing removes
# the options it processes, which should only leave optional filenames to process.
my %args = map {$_ => 1} @ARGV; # make the ARGS into a hash

# -----------------
# Subroutines
# -----------------

sub print_help {    # TODO move to Pod::Usage
    print "Syntax:";
    print "  get-screen-shots.pl [--help --setup --login] [<file name> ...]\n";
    print "  --help - print help and exit.\n";
    print "  --setup - Do the setup.pl screens, which will create a new company. Defaults to not processing if not specified.\n";
    print "  --login - Do the login.pl screens. Defaults to not processing if not specified.\n";
    print "  --debug - Turn on various debug actions.";
    print "  * Optional <file name> is a screenshot file name ending with '.png'. If no <file name>'s are specified, then process all screenshots.\n";
    print "  * At least one of --setup or --login must be specified.\n";
    print "  * Wildcards are not accepted in file names.\n\n";
    print "Example Usage:\n";
    print "  PGHOSTADDR='172.16.1.218' PGPORT='5001' PGDATABASE='example_inc' PGUSER='postgres' PGPASSWORD='abc' \\\n";
    print "  LSMB_ADMIN_USERNAME='admin' LSMB_ADMIN_PASSWORD='asdfg' LSMB_BASE_URL='http://vmwareledgerdev.local:5000'\\\n";
    print "  perl get-screen-shots.pl --login system--defaults.png\n\n"; # use perl here because /usr/bin/perl is not the correct perl.
    print "  PGHOSTADDR='172.16.1.218' PGPORT='5001' PGDATABASE='example_inc' PGUSER='postgres' PGPASSWORD='abc' \\\n";
    print "  LSMB_ADMIN_USERNAME='admin' LSMB_ADMIN_PASSWORD='asdfg' LSMB_BASE_URL='http://vmwareledgerdev.local:5000' \\\n";
    print "  perl get-screen-shots.pl --debug --setup\n\n"; # use perl here because /usr/bin/perl is not the correct perl.
}

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
            WHERE 	screen_file_name ilike 'top-level--%'  -- Only need the top level not the recursive intermediates.
            ORDER BY screen_file_name
SQL
    my $sth = $conn->prepare($sql);
    $sth -> execute();
    return $sth
}

sub disable_toaster ($conn) {
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
    send_data_to_field($driver, "//input[\@name='username']", $user_name);

    # Fill Password
    send_data_to_field($driver, "//input[\@name='password']", $user_password);

    # Fill Company
    send_data_to_field($driver, "//input[\@name='company']", $company);
}

# If an error dialog is visible, close it.
sub close_error ($driver) {
    eval {
        my $error_element = $driver->find_element_by_xpath("//div[\@id='errorDialog']/*/span[\@role='button']");
        if ($error_element != 0) {
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

# Attempt to select the password tab in the preferences screen.
sub select_preferences_tab ($driver) {
    # https://github.com/ledgersmb/LedgerSMB/blob/f3db4354d9cc8e2f98288ecd687f20a5b44a1b36/xt/lib/Pherkin/Extension/pageobject_steps/nav_steps.pl#L177
    my $preference_tab_element = $driver->find_element_by_xpath(".//*[\@role='tab' and text()='Preferences']");
    if ($preference_tab_element == 0) { die "Preferences xpath element not defined"; }
    $preference_tab_element->click();
}

sub open_database($database_name) {
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
    my $dbh = DBI->connect("dbi:Pg:dbname=$database_name", undef, undef, {
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
sub preprocess_dummy($driver, $screenshot_filename) { print "  Pre Processing Example\n"; }

# A dummy post-process subroutine for testing
sub postprocess_dummy($driver) { print "  Post Processing Example\n"; }

# For troubleshooting, this subroutine can be used in either the pre or post processing.
sub wait_for_keyboard($driver) {
    # For troubleshooting, pause the see the last screen.
    print "Press Enter to continue: ";
    <STDIN>;
    print "\n";
}

# Scroll to the default save button of
sub scroll_to_save_button($driver) {
    my $save_element = $driver->find_element_by_xpath(".//*[\@id='action-save-defaults' and \@role='button']");
    $driver-> execute_script('arguments[0].scrollIntoView(true)', $save_element);
}

# Scroll to the bottom and create a new screenshot of the bottom
# of the screen.
sub post_process_system_defaults($driver) {
    scroll_to_save_button($driver);
    my $new_name = "${screen_shot_base_path}/system--defaults-1.png";
    print "  Processing: $new_name\n";
    $driver->capture_screenshot($new_name);
}

# Contains processing data for each screenshot that needs non-default processing.
# If the file name is not found as a hash key, then the 'default' hash entry will be used.
#   h    = resize the screen to this height prior to the screenshot
#   w    = resize the screen to this width prior to the screenshot
#   pre  = subroutine to run after loading the screen, but prior to the screenshot
#   post = subroutine to run after the screen shot. In most cases this is used to process something else on the screen like a tab.
# Example:
#    'login.png' => { h => 520, w => 520,  pre => \&preprocess_dummy, post => \&postprocess_dummy},
my %processing_config = (
    'default'                         => { h => 820, w => 1200},  # The default screen resize values if there is no match file name match
    $login_screenshot_file_name       => { h => 520, w =>  520},  # No need for a lot of empty space
    $welcome_screenshot_file_name     => { h => 700, w => 1280, pre => \&login},  # Make the screen wider since it includes the welcome text
    'preferences-preferences.png'     => { h => 820, w => 1200, pre => \&select_preferences_tab},
    'system--defaults.png'            => { h => 820, w => 1300, post => \&post_process_system_defaults},
    'setup-pl-login.png',             => { h => 550, w =>  520, pre => \&setup_login_create_db_data},
    'setup-pl-select-coa-country.png' => { h => 820, w =>  820, pre => \&setup_select_coa_country },
    'setup-pl-select-coa.png'         => { h => 550, w =>  520, pre => \&setup_select_coa},
    'setup-pl-load-templates.png'     => { h => 400, w =>  420 },
    'setup-pl-create-user.png'        => { h => 680, w =>  650, pre => \&setup_enter_user},
    'setup-pl-create-user-completion.png' => { h => 780, w =>  640},
);

# If the resize value is different than the current screen dimensions
# then resize the screen.
sub check_and_resize($driver, $to_height, $to_width) {
    my $window_size = $driver->get_window_size();
    if ($window_size->{'height'} == $to_height && $window_size->{'width'} == $to_width) {
        return; # No change needed
    }
    print "  Set screen to: $to_height, $to_width\n";
    $driver->set_window_size($to_height, $to_width);
    sleep(0.1); # May not need this, but should verify before removing.
}

# Process a screenshot
# If $do_screenshot is false, then skip the screen capture, but still perform all pre and post subroutines.
# If $check_error_dialog is false, then skip checking for the error dialog.
sub process_screen( $driver, 
                    $url, 
                    $screen_file_name,
                    $id_to_capture,
                    $check_error_dialog=1, 
                    $do_screenshot=1) {

    # If only processing specific screenshot file names, then skip the others
    # Always need to process login or nothing else works.
    # Note that the actual login is done in the pre processing of the welcome screen.
    if ((%args) && (!exists $args{$screen_file_name})) {
        if (($screen_file_name eq $login_screenshot_file_name)
            || ($screen_file_name eq $welcome_screenshot_file_name)) {
            # We have do login and welcome, even if we do not capture the screenshot
            $do_screenshot = 0;
        }
        else {
            return;
        }
    }

    print "Processing: $screen_file_name\n";

    # If the URL is not supplied, then proceed without any navigation. 
    # The screen may have been updated by some previous action.
    if (defined $url) {
        # Navigate to the screen
        $driver->get("$base_url/$url");
        sleep($capture_delay);          # Wait for screen to load
    }
    else {
        print "  Skipping navigation\n";
    }

    # If error dialog is showing, close it.
    if ($check_error_dialog) {
        close_error($driver);
    }

    # Get the configuration, either specific to the screen file name or the default.
    my %config = (exists $processing_config{$screen_file_name}) ? $processing_config{$screen_file_name}->%* : $processing_config{default}->%* ;

    # Resize if necessary
    check_and_resize($driver, $config{h}, $config{w} );
    sleep(0.2);

    # If defined do pre processing, such as loading data specific to this screen.
    if (defined $config{pre}) {
        $config{pre}($driver);
    }
    if ($do_debug) { $driver->debug_off; } # Don't need to dump screenshots.
    if ($do_screenshot) {
        # Capture the screenshot
        if (defined $id_to_capture) {
            my $main_div = $driver->find_element_by_xpath("//*[\@id='$id_to_capture']"); # ignore menu in screenshot
            $main_div->capture_screenshot("$screen_shot_base_path/$screen_file_name");
        }
        else {
            $driver->capture_screenshot("$screen_shot_base_path/$screen_file_name");
        }
    }
    else {
        print "  Skipping screenshot\n";
    }
    if ($do_debug) { $driver->debug_on; } # Reset after screenshots.

    # If defined, do post processing.
    if (defined $config{post}) {
        $config{post}($driver);
    }

}

# Query the database menu structure and do requested screenshots based on login.pl
sub process_login_screenshots($conn, $driver, ) {
    # Make the toaster go away for these tests by disabling it in the database
    disable_toaster($conn);

    # Get the menu structure from the database
    my $menu_structure_data = get_menu_structure($conn);

    # Grab a screenshot of the LSMB login screen.
    process_screen($driver, "login.pl", $login_screenshot_file_name, 'maindiv', 0);
    # Click Login Button
    click_button($driver, "//lsmb-button[\@id='login']");

    # Grab a screenshot of the welcome screen after login
    process_screen($driver, undef, 'welcome.png', 'maindiv', 0);

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
            process_screen($driver, $ref->{url}, 'preferences-password.png', 'maindiv');
            # Then the actual preferences tab. The navigation code is in the preprocessing subroutine.
            process_screen($driver, undef, 'preferences-preferences.png', 'maindiv');
        }
        else {
            process_screen($driver, $ref->{url}, $ref->{screen_file_name}, 'maindiv');
        }
        # have to process tabs for general-journal--year-end.png
        # have to process tabs for contacts person company
    }

    # Process the logout screenshot as the last item
    process_screen($driver, $logout_ref->{url}, $logout_ref->{screen_file_name}, 'maindiv');

    enable_toaster($conn);
    $menu_structure_data->finish();
}

sub find_select_dropdown($driver, $xpath) {
    my $dropdown = $driver->find_element_by_xpath($xpath);
    if ($dropdown == 0) { die "Not able to find xpath: $xpath"; }
    $driver->mouse_move_to_location(element => $dropdown);
    $driver->click();
}

sub scroll_dropdown_and_select($driver, $wanted_selection) {
    my $selection = $driver->find_element_by_xpath($wanted_selection);
    if ($selection == 0) { die "Not able to find selection: $wanted_selection"; }
    $driver-> execute_script('arguments[0].scrollIntoView(true)', $selection);
    $driver->mouse_move_to_location(element => $selection);
    $driver->click();
}

sub click_button($driver, $xpath) {
    my $button_element = $driver->find_element_by_xpath($xpath);
    if ($button_element == 0) { die "Button xpath not found: $xpath"; }
    $driver->mouse_move_to_location(element => $button_element);
    $driver->click();
}

sub send_data_to_field($driver, $xpath, $field_text) {
    my $element = $driver->find_element_by_xpath($xpath);
    if ($element == 0) { die "xpath element not found: $xpath"; }
    $element->send_keys($field_text);
}

# Enter the setup.pl login credentials
sub setup_login_create_db_data($driver) {
    # Select postgres user from dropdown
    my $combobox_element = $driver->find_element_by_xpath(".//input[\@id='s-user']");
    if ($combobox_element == 0) { die "user xpath element not defined"; }
    $combobox_element->send_keys($ENV{'PGUSER'});

    # Enter postgres user password
    my $password_element = $driver->find_element_by_xpath("//input[\@type='password']");
    if ($password_element == 0) { die "Password xpath element not defined"; }
    $password_element->send_keys($ENV{'PGPASSWORD'});

    # Enter new database name
    my $company_element = $driver->find_element_by_xpath("//input[\@name='database']");
    if ($company_element == 0) { die "Company xpath element not defined"; }
    $company_element->send_keys($ENV{'PGDATABASE'});
}

# Select the a country for the COA.
# Returns 1 on error.
sub setup_select_coa_country ($driver) {
    
    # Find the dropdown
    find_select_dropdown($driver, "//table[\@id='coa-lc']");

    # Scroll United States into view and click it
    scroll_dropdown_and_select($driver, "//*[contains(text() ,'United States')]");
}

# Select the CoA from the dropdown.
sub setup_select_coa($driver) {

    # Find the dropdown
    find_select_dropdown($driver, ".//table[\@id='chart']");

    # Scroll GeneralHierarchical.xml into view and click it
    scroll_dropdown_and_select($driver, "//*[contains(text() ,'GeneralHierarchical.xml')]");
}

# Enter the admin user info
sub setup_enter_user($driver) {
    send_data_to_field($driver, "//input[\@id='username']", "admin");
    send_data_to_field($driver, "//input[\@id='password']", "asdfg");
    send_data_to_field($driver, "//input[\@id='first-name']", "Ad");
    send_data_to_field($driver, "//input[\@id='last-name']", "Min");
    send_data_to_field($driver, "//input[\@id='employeenumber']", "1");
    send_data_to_field($driver, "//input[\@id='dob']", "1/1/2000");
    send_data_to_field($driver, "//input[\@id='ssn']", "0");

    # Accept default new user, nothing to do

    # Select salutation
    find_select_dropdown($driver, "//table[\@id='salutation-id']");
    scroll_dropdown_and_select($driver, "//*[contains(text() ,'Mr.')]");

    # Country
    find_select_dropdown($driver, "//table[\@id='country-id']");
    scroll_dropdown_and_select($driver, "//*[contains(text() ,'United States')]");

    # Permissions
    find_select_dropdown($driver, "//table[\@id='perms']");
    scroll_dropdown_and_select($driver, "//*[contains(text() ,'Full Permissions')]");
}

# Gather the screenshots based on setup.pl
sub process_setup_screenshots ($driver) {

    # Grab a screenshot of the LSMB setup login screen with data.
    process_screen($driver, "setup.pl", "setup-pl-login.png", undef, 0);
    # Click Create Button
    click_button($driver, "//span[\@id='lsmb/SetupLoginButton_1']");
    sleep(7.0); # Creating the database takes a few seconds

    # Grab a screenshot of the COA Country selection United States screen with data
    process_screen($driver, undef, "setup-pl-select-coa-country.png", undef, 0);
    # click the next button
    click_button($driver, "//span[\@id='action-select-coa']");

    sleep(2.5); # Wait for CoA files to be scanned and loaded
    # Grab a screenshot of the COA GeneralHierarchical.xml selection screen
    process_screen($driver, undef, "setup-pl-select-coa.png", undef, 0);
    # click the next button
    click_button($driver, "//span[\@id='action-select-coa']");

    sleep(3.5); # Wait for template files to be scanned
    # Grab a screenshot of the Load Templates screen, we use the defaults so no pre-loading of data
    process_screen($driver, undef, "setup-pl-load-templates.png", undef, 0);
    # click the Load Templates button
    # sleep(1.5);
    click_button($driver, ".//span[\@widgetid='action--select-templates']");


    sleep(3.5); # Wait for user data to appear
    # Grab a screenshot of the User screen
    process_screen($driver, undef, "setup-pl-create-user.png", undef, 0);
    click_button($driver, "//span[\@widgetid='action--create-initial-user']");

    sleep(2.0);
    # Grab the final screen
    process_screen($driver, undef, "setup-pl-create-user-completion.png", undef, 0);
}

# If company already exists then die.
sub company_exist() {
    my $dbh = DBI->connect('dbi:Pg:dbname=postgres', $ENV{PGUSER}, $ENV{PGPASSWORD}, {
            AutoCommit => 0,
            ReadOnly => 1,
            PrintError => 1,
            RaiseError =>  1 })
        or die "Unable to connect: $DBI::errstr\n";
    # print "Connected to the '$dbh->{pg_db}' database.\n";
    my $sth = $dbh->prepare('SELECT 1 FROM pg_database WHERE datname=$1;');
    $sth -> execute($company);
    my $result = ($sth->rows > 0);
    $sth->finish;
    $dbh->disconnect(); 
    return $result;
}

sub role_exist() {
    my $dbh = DBI->connect('dbi:Pg:dbname=postgres', $ENV{PGUSER}, $ENV{PGPASSWORD}, {
            AutoCommit => 0,
            ReadOnly => 1,
            PrintError => 1,
            RaiseError =>  1 })
        or die "Unable to connect: $DBI::errstr\n";
    # print "Connected to the '$dbh->{pg_db}' database.\n";
    my $sth = $dbh->prepare('SELECT 1 FROM pg_roles WHERE rolname=$1;');
    $sth -> execute($user_name);
    my $result = ($sth->rows > 0);
    $sth->finish;
    $dbh->disconnect();
    return $result;
}

# -----------------
# Main
# -----------------

# Set up Firefox driver
my $firefox_driver = Selenium::Firefox->new ( firefox_profile => $profile );
$firefox_driver->delete_all_cookies(); # Get rid of session expired notice.
if ($do_debug) { $firefox_driver->debug_on; }

if ($do_setup) {
    die "Company '$company' already exists. Setup screenshots cannot be created." if company_exist();
    die "User '$user_name' already exists. Setup screenshots cannot be created." if role_exist();

    # Do Setup
    process_setup_screenshots($firefox_driver);
}

if ($do_login) {
    die "Company '$company' does not exist. Menu screenshots cannot be created." if !company_exist();
    die "User '$user_name' does not exist. Menu screenshots cannot be created." if !role_exist();

    my $dbh = open_database($company);

    # Do Login
    process_login_screenshots($dbh, $firefox_driver);
    $dbh->disconnect();
}

# Done, clean up
$firefox_driver->shutdown_binary;

# Misc Notes
# https://github.com/ledgersmb/LedgerSMB/blob/c799718433e18f6ffce6e2eda1cd15df178b6999/xt/lib/PageObject/App/Login.pm#L35
# https://github.com/perl-weasel/weasel/blob/58aea10134b46bf10b1e8f97c595abe53ac6a801/lib/Weasel/FindExpanders/HTML.pm#L130
