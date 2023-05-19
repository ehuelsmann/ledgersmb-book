#!/usr/bin/perl

# get-screen-shots.pl
#
# Query a live LSMB instance and save screenshots to PNG files.
#
# Does not add meta data to the images because they could change each time.
#
# A small subset of the screens have default dates that will change each different
# day the screens are grabbed. If mask regions are defined for a screen, then these regions will
# be ignored during the comparison.  Be aware that perl image compare code is really, and I mean
# really, slow so be patient.
#
# The menu derived screen shot file name format is
#   <parent label>--<parent label>--<label> 
# All labels are lowercased and spaces replaced with a single hyphen ('-'). 
# Parent labels are repeated as necessary to fully describe the menu path.
#
# The screenshots use the data expected in the book's Getting Started section.
# Therefor, the user is 'admin' and the company name is 'example_inc'.
# 
# Runs in about 2240 seconds or with 180 screenshots about 12.4 seconds per screenshot.
#

use warnings;
use strict;
# use Time::Piece;
use Time::HiRes;

# use Data::Dumper;
use Diagnostics;
use Carp 'verbose'; # 'verbose'
$SIG{ __DIE__ } = \&Carp::croak;

use Getopt::Long;
# use Pod::Usage; # TODO convert print statements to real pod help

use Selenium::Firefox;
use Selenium::Remote::Driver;
use Selenium::Firefox::Profile;
use Selenium::Screenshot;
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
my $menu_screenshot_file_name = 'menu.png';
my $password_screenshot_file_name = 'preferences-password.png';
my $system_defaults_screenshot_file_name = 'system--defaults.png';
my $processing_count = 0;
my $start_time = Time::HiRes::gettimeofday();

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
my %screenshots_to_process = map {$_ => 1} @ARGV; # make the ARGS into a hash

# During processing, the code may decide to process screenshots manually and out of sequence.
# If it does, then the screenshot file name is added to this var so that it won't be processed again.
my %screenshots_to_ignore;

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
    print "  * Must start with a clean LSMB installation: no companies and no users that match the environment variables.\n";
    print "  * Wildcards filenames are not accepted in file names.\n\n";
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

# If an error alert is open, close it.
sub close_alert ($driver) {
    eval {
        my $alert_txt = $driver->get_alert_text();
        print "  Found Alert: $alert_txt";
        $driver->dismiss_alert;
    };
    my $an_error = $@; 
    if ($an_error) {
        if ( index($an_error, 'no such alert at') == -1 ) {
            # Print any unexpected errors
            print "  $an_error";
        }
        # On error no need to wait.
    }
    else {
        print "  Dismissing Alert.\n";
        sleep($capture_delay);      # Wait for dialog to dismiss.
    }
}

# If an error window is visible, close it.
sub close_error ($driver) {
    eval {
        my $error_element = $driver->find_element_by_xpath("//div[\@id='errorDialog']/*/span[\@role='button']");
        if ($error_element) {
            $driver->mouse_move_to_location(element => $error_element);
            $driver->click();
        }
    };
    my $an_error = $@; 
    if ($an_error) {
        if ( index($an_error, 'Origin element is not displayed at') == -1) {
            # Print any unexpected errors
            print "  $an_error\n";
        }
        # On error no need to wait.
    }
    else {
        print "  Dismissing Error dialog.\n";
        sleep($capture_delay);      # Wait for dialog to dismiss.
    }
}

# Attempt to select the password tab in the preferences screen.
sub select_preferences_tab ($driver) {
    # https://github.com/ledgersmb/LedgerSMB/blob/f3db4354d9cc8e2f98288ecd687f20a5b44a1b36/xt/lib/Pherkin/Extension/pageobject_steps/nav_steps.pl#L177
    my $preference_tab_element = $driver->find_element_by_xpath("//*[\@role='tab' and text()='Preferences']");
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

# Scroll to the default save button
sub scroll_to_save_button($driver, $xpath) {
    my $save_element = $driver->find_element_by_xpath($xpath);
    $driver-> execute_script('arguments[0].scrollIntoView(true)', $save_element);
    return $save_element;
}

# Scroll to the bottom and create a new screenshot of the bottom
# of the screen.
sub post_process_system_defaults($driver) {
    scroll_to_save_button($driver, ".//*[\@id='action-save-defaults' and \@role='button']");
    my $new_name = "${screen_shot_base_path}/system--defaults-1.png";
    print "  Processing: $new_name\n";
    $driver->capture_screenshot($new_name);
}

# Set password expiration in system defaults
sub pre_process_system_defaults($driver) {
    send_data_to_field($driver, "//input[\@id='company-name']", 'Example Inc.');
    send_data_to_field($driver, "//textarea[\@id='company-address']", "215 Example St\nAny City, CA");
    send_data_to_field($driver, "//input[\@id='company-phone']", '555 836 2255');
    send_data_to_field($driver, "//input[\@id='businessnumber']", '12345');
    send_data_to_field($driver, "//input[\@id='default-email-from']", 'info@example.com');

    find_select_dropdown($driver, "//table[\@id='default-country']");
    scroll_dropdown_and_select($driver, "//*[contains(text(),'United States')]");

    find_select_dropdown($driver, ".//table[\@id='default-language']");
    scroll_dropdown_and_select($driver, "//*[contains(text(), 'English')]");

    send_data_to_field($driver, "//input[\@id='password-duration']", '180');
}

# Change password after setting expiration.
sub renew_password($driver) {
    send_data_to_field($driver, "//input[\@id='old-pw']", $user_password);
    send_data_to_field($driver, "//input[\@id='new-pw']", $user_password);
    send_data_to_field($driver, "//input[\@id='verify-pw']", $user_password);
}

# Contains processing data for each screenshot that needs non-default processing.
# If the file name is not found as a hash key, then the 'default' hash entry will be used.
#   h    = resize the screen to this height prior to the screenshot
#   w    = resize the screen to this width prior to the screenshot
#   pre  = subroutine to run after loading the screen, but prior to the screenshot
#   post = subroutine to run after the screen shot. In most cases this is used to process something else on the screen like a tab.
#   ids  = the CSS ids that represent elements to ignore when comparing screenshot images.  Typically these are date widget ids.
# Example:
#    'login.png' => { h => 520, w => 520,  pre => \&preprocess_dummy, post => \&postprocess_dummy},
my %processing_config = (
    'default'                         => { h => 820, w => 1200}, # The default screen resize values if there is no file name match
    $login_screenshot_file_name       => { h => 520, w =>  520, pre => \&login},  # No need for a lot of empty space
    $welcome_screenshot_file_name     => { h => 910, w =>  969}, # Make the screen narrower since so both welcome text and menu are visible
    $menu_screenshot_file_name        => { h => 820, w => 1280}, # Only capturing the menu, but it needs to be longer.
    $password_screenshot_file_name     => { h => 620, w =>  520, pre => \&renew_password},

    'preferences-preferences.png'     => { h => 820, w => 1200, pre => \&select_preferences_tab},
    'system--defaults.png'            => { h => 820, w => 1300, pre => \&pre_process_system_defaults, post => \&post_process_system_defaults},
    'setup-pl-login.png',             => { h => 550, w =>  520, pre => \&setup_login_create_db_data},
    'setup-pl-select-coa-country.png' => { h => 820, w =>  820, pre => \&setup_select_coa_country },
    'setup-pl-select-coa.png'         => { h => 550, w =>  520, pre => \&setup_select_coa},
    'setup-pl-load-templates.png'     => { h => 400, w =>  420 },
    'setup-pl-create-user.png'        => { h => 680, w =>  650, pre => \&setup_enter_user},
    'setup-pl-create-user-completion.png' => { h => 780, w =>  640},

    'ap--add-transaction.png'         => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ap--debit-invoice.png'           => { h => 820, w => 1200, ids => ['widget_transdate'] },
    'ap--debit-note.png'              => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ap--vendor-invoice.png'          => { h => 820, w => 1200, ids => ['widget_transdate'] },
    'ap--vouchers--ap-voucher.png'    => { h => 820, w => 1200, ids => ['widget_description', 'widget_batch-number'] },
    'ap--vouchers--invoice-vouchers.png' => { h => 820, w => 1200, ids => ['widget_description', 'widget_batch-number'] },

    'ar--add-return.png'              => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ar--add-transaction.png'         => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ar--credit-invoice.png'          => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ar--credit-note.png'             => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ar--sales-invoice.png'           => { h => 820, w => 1200, ids => ['widget_crdate', 'widget_transdate'] },
    'ar--vouchers--ar-voucher.png'    => { h => 820, w => 1200, ids => ['widget_description', 'widget_batch-number'] },
    'ar--vouchers--invoice-vouchers.png' => { h => 820, w => 1200, ids => ['widget_description', 'widget_batch-number'] },



    
    ''           => { h => 820, w => 1200, ids => [] },
    ''           => { h => 820, w => 1200, ids => [] },
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
    sleep(0.2); # May not need this, but should verify before removing.
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
    if ((%screenshots_to_process) && (!exists $screenshots_to_process{$screen_file_name})) {
        if ($screen_file_name eq $login_screenshot_file_name) {
            # We have to do login, even if we do not capture the screenshot
            $do_screenshot = 0;
        }
        else {
            return;
        }
    }

    print "Processing: $screen_file_name\n";
    $processing_count += 1;

    if ((%screenshots_to_ignore) && (exists $screenshots_to_ignore{$screen_file_name})) {
        print "  Skipping, has been previously processed\n";
        return;
    }
    
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

    # Close any alerts showing
    close_alert($driver);

    # Get the configuration, either specific to the screen file name or the default.
    my %config = (exists $processing_config{$screen_file_name}) ? $processing_config{$screen_file_name}->%* : $processing_config{default}->%* ;

    # Resize if necessary, has delay
    check_and_resize($driver, $config{h}, $config{w} );

    # If defined do pre processing, such as loading data specific to this screen.
    if (defined $config{pre}) {
        $config{pre}($driver);
    }

    # Capture the screenshot
    if ($do_screenshot) {
        capture_compare_save_screen($driver, $id_to_capture, $screen_file_name, %config);
    }
    else {
        print "  Skipping screenshot\n";
    }

    # If defined, do post processing.
    if (defined $config{post}) {
        $config{post}($driver);
    }

}

# If screenshot has changed, then capture the new screen
#
# If given a list ids, mask those widgets, then compare with existing screenshot.
# If different, then save the new version.
sub capture_compare_save_screen($driver, $id_to_capture, $screen_file_name, %config) {
    my $screen_shot_element = $driver;
    if (defined $id_to_capture) {
        # If an element id is provided, then only capture that element's screen
        $screen_shot_element = $driver->find_element_by_xpath("//*[\@id='$id_to_capture']"); # ignore menu in screenshot
    }
    # Find any elements to exclude when comparing screenshots
    my @exclude = map {
        print "  Searching for element name: $_\n";
        my $element = $driver->find_element_by_id($_);
        if ($element) {
            my $rect = {
                size => $element->get_size,
                location => $element->get_element_location
            };
            $rect;
        }
        else {
            print "  Unable to find element: $_ for screenshot $screen_file_name. Line: ", __LINE__, "\n";
            ();
        }
    }  $config{ids}->@*;

    # print Dumper(\@exclude);

    if ($do_debug) { $driver->debug_off; } # Don't need to debug or dump screenshot
    my $new_screen_shot = Selenium::Screenshot->new(
        png => $screen_shot_element->screenshot,
        exclude => [ @exclude ],
        folder => "$screen_shot_base_path",
        threshold => 1, # 1 percent different
        metadata => {
            key => "$screen_file_name",
        }
    );
    if ($do_debug) { $driver->debug_on; } # Reset debug after taking screenshot

    # Get the old image
    my $old_img = Imager->new;
    $old_img->read(file=>"$screen_shot_base_path/$screen_file_name")
        or print "  Image $screen_file_name, load error: $old_img->errstr\n";

    # Check that the images can be compared
    if (($old_img->getwidth()     != $new_screen_shot->png->getwidth()) 
        or ($old_img->getheight() != $new_screen_shot->png->getheight())
        or (!$old_img))  {
            # If not able to compare then just save the new image
            $new_screen_shot->save;
            print "  🟢 Updated screenshot based on size diff or new\n";
            return;
    }

    # Compare the screenshot
    if ($new_screen_shot->compare($old_img)) {
        print "  No update, screenshot is same as file\n";
    }
    else {
        # Save the screenshot
        $new_screen_shot->save;
        print "  🟢 Updated screenshot based on comparison\n";
    }
}

# Query the database menu structure and do requested screenshots based on login.pl
sub process_login_screenshots($conn, $driver) {
    # Make the toaster go away for these tests by disabling it in the database
    disable_toaster($conn);

    # Get the menu structure from the database
    my $menu_structure_data = get_menu_structure($conn);

    # Grab a screenshot of the LSMB login screen
    process_screen($driver, "login.pl", $login_screenshot_file_name, undef, 0);
    $screenshots_to_ignore{$login_screenshot_file_name} = 1;
    # Click Login Button
    click_button($driver, "//lsmb-button[\@id='login']");

    # Grab a screenshot of the welcome screen after login
    sleep(1.5); # Wait for menus to get setup
    process_screen($driver, undef, $welcome_screenshot_file_name, undef, 0);
    $screenshots_to_ignore{$welcome_screenshot_file_name} = 1;

    # print Dumper($driver->get_all_cookies());

    if (scalar %screenshots_to_process == 0) {
        # Unless processing a specific set of screenshots, process the user defaults screen first, then add to ignore array
        # The reason we do it here is so that the password does not expire right away and
        # to show the default information in subsequent screenshots.
        process_screen($driver, 'erp.pl?action=root#/configuration.pl?action=defaults_screen', $system_defaults_screenshot_file_name, 'maindiv', 0);
        $screenshots_to_ignore{$system_defaults_screenshot_file_name} = 1;
        my $save_default = scroll_to_save_button($driver, ".//*[\@id='action-save-defaults' and \@role='button']");
        $save_default->click();

        # Reset the user password so the password expires default take effect
        process_screen($driver, 'erp.pl?action=root#/user.pl?action=preference_screen', $password_screenshot_file_name, 'maindiv');
        $screenshots_to_ignore{$password_screenshot_file_name} = 1;
        #click_button($driver, ".//span[\@id='pw-change']");
        #click_button($driver, ".//span[\@widgetid='pw-change']");
        my $xpath = ".//span[\@id='pw-change']";
        my $button_element = $driver->find_element_by_xpath($xpath);
        if ($button_element == 0) { die "Button xpath not found: $xpath"; }
        $button_element->click();

        # Then the actual preferences tab. The navigation code is in the preprocessing subroutine.
        process_screen($driver, undef, 'preferences-preferences.png', 'maindiv');
        $screenshots_to_ignore{'preferences-preferences.png'} = 1;
    }

    my $logout_ref; # Create reference for logout, because it will be deferred and processed after all other screenshots.

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

            # Note that if we are only processing certain menus, then navigation is skipped
            # and the processing of the preferences tab fails.
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
    $element->clear();
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
    scroll_dropdown_and_select($driver, "//*[contains(text(), 'United States')]");
}

# Select the CoA from the dropdown.
sub setup_select_coa($driver) {

    # Find the dropdown
    find_select_dropdown($driver, ".//table[\@id='chart']");

    # Scroll GeneralHierarchical.xml into view and click it
    scroll_dropdown_and_select($driver, "//*[contains(text(), 'GeneralHierarchical.xml')]");
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


if ($do_setup) {
    die "Processing specific screenshots is currently broken when using --setup."  if (%screenshots_to_process);
    die "Company '$company' already exists. Setup screenshots cannot be created." if company_exist();
    die "User '$user_name' already exists. Setup screenshots cannot be created." if role_exist();

    # Set up Firefox driver
    my $firefox_driver = Selenium::Firefox->new ( firefox_profile => $profile );
    $firefox_driver->delete_all_cookies(); # Get rid of session expired notice.
    if ($do_debug) { $firefox_driver->debug_on; }

    # Do Setup
    process_setup_screenshots($firefox_driver);

    # Done, clean up
    $firefox_driver->shutdown_binary;
}

if ($do_login) {
    die "Company '$company' does not exist. Menu screenshots cannot be created." if !company_exist();
    die "User '$user_name' does not exist. Menu screenshots cannot be created." if !role_exist();

    # Set up Firefox driver
    my $firefox_driver = Selenium::Firefox->new ( firefox_profile => $profile );
    $firefox_driver->delete_all_cookies(); # Get rid of session expired notice.
    if ($do_debug) { $firefox_driver->debug_on; }

    my $dbh = open_database($company);

    # Do Login
    process_login_screenshots($dbh, $firefox_driver);
    $dbh->disconnect();

    # Done, clean up
    $firefox_driver->shutdown_binary;
}

my $stop_time = Time::HiRes::gettimeofday();
my $interval = $stop_time - $start_time;
my $per = $interval / $processing_count;
printf ("Processed: %d screens in %0.1f seconds ( %0.1f secs per screen).\n", $processing_count, $interval, $per);

# Misc Notes
# https://github.com/ledgersmb/LedgerSMB/blob/c799718433e18f6ffce6e2eda1cd15df178b6999/xt/lib/PageObject/App/Login.pm#L35
# https://github.com/perl-weasel/weasel/blob/58aea10134b46bf10b1e8f97c595abe53ac6a801/lib/Weasel/FindExpanders/HTML.pm#L130
# also check out https://metacpan.org/pod/Future::Utils those can help to limit the number of "futures being in-flight".
# https://metacpan.org/pod/Future::AsyncAwait
# https://metacpan.org/pod/IO::Async
