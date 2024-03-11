#!/usr/bin/perl

# gather-db-info.pl
#
# Access a running LedgerSMB Postgres database and
# retrieve information to create include files for the LedgerSMB Book.
#
# The user accessing the database requires enough privilages
# to read all tables.

use warnings;
use strict;
use diagnostics;
use Time::Piece;

use DBI;

use feature 'signatures';
no warnings "experimental::signatures";

# Where to put the resulting include files.
# Assumes we are running from the scripts directory.
my $tex_include_dir = '../auto-generated';

# Write the tex string to the given file name.
sub write_file($latex, $latex_file_name) {
        my $file_path = "$tex_include_dir/$latex_file_name";
        open(my $fh, '>:encoding(UTF-8)', $file_path) 
            or die "Could not open file '$file_path' $!";
        print $fh $latex;
        close $fh;
}

sub get_lsmb_db_version($conn) {
	my $sql = <<'SQL';
        SELECT  value
        FROM    defaults
        WHERE   setting_key = 'version';
SQL
    my $sth = $conn->prepare($sql)
        or die "failed to prepare statement $DBI::errstr";
    $sth->execute 
        or die "failed to execute statement $DBI::errstr";
    my $row = $sth->fetch 
        or die "failed to fetch data $DBI::errstr";
    return $row->[0];
}

# Basic characater conversion for tex characters that must be escaped.
# For example in tex a bare '_' must be excaped to '\_'.
# Normally these characters need escape: \ { } _ ^ # & $ % ~
sub to_tex($text_in) {
    # Key can only be a single character. 
    my %map = (
        '_' => '\_',
        '<' => '\textless{}',
        '>' => '\textgreater{}',
        '*' => '$\ast$',
        '&' => '\&',
        '$' => '\$',
        '%' => '\%'
    );
    my $match_chars = join '', keys %map;
    my $result = $text_in =~ s/([$match_chars])/$map{$1}/gr;
    return $result;
}

# scan the text for bare words that are glossary entries.
sub make_glossary_entries ($text) {
    my %map = (
        '\bGL\b' => '\gls{GL} \index{GL}\index{General Ledger}',
        '\bAR\b' => '\gls{AR} \index{AR}\index{Accounts Receivable}',
        '\bAP\b' => '\gls{AP} \index{AP}\index{Accounts Payable}',
    );
    my $new_text = $text;
    while (my ($key, $replacement) = each %map) {
        $new_text = $new_text =~ s/$key/$replacement/gr;
    }
    return $new_text;
}

# create the description begining.
sub description_prolog {
    return '\begin{description}';
}

# create the description end.
sub description_epilog {
    return '\end{description}';
}

# Access the database and get all of the role comments
# then process text -> tex, and write to the given
# file name.
sub get_format_role_comments($file_name, $conn) {
    # The LSMB role names contain the company name, which is the same as the database name.
    # Remember that SQL LIKE comparison uses '_' for any single character.
    my $role_name_format = "lsmb\\_$conn->{pg_db}\\_\\_%";

	my $sql = <<'SQL';
        SELECT  split_part(r.rolname, '__', 2) AS rolename, 
                COALESCE (psd.description, '@@@') AS desc
        FROM    pg_catalog.pg_roles r 
        LEFT OUTER JOIN pg_shdescription psd ON r.oid = psd.objoid
        INNER JOIN pg_class c ON c.relname = 'pg_authid'
        INNER JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'pg_catalog'
        WHERE   r.rolname ilike ?
        ORDER BY 1;
SQL
    # Accumulate the Latex to write to file.
    my $date = localtime->strftime('%B %e, %X %Y %Z');
    my $lsmb_version = get_lsmb_db_version($conn);
    my @tex_array = "\nAuto generated using LedgerSMB version ${lsmb_version} on $date.\n";
    push (@tex_array, description_prolog());

    my $sth = $conn->prepare($sql);
    $sth -> execute($role_name_format);
    while (my $ref = $sth->fetchrow_hashref('NAME_lc') ) {
        print "Found Before Processing: $ref->{rolename} -> '$ref->{desc}'\n";
        my $role_name = to_tex($ref->{rolename});
        my $role_desc = to_tex($ref->{desc});

        # Convert bare words like GL to glossary entries and index entries.
        $role_desc = make_glossary_entries($role_desc);

        # Create an index for the role name
        my $index = $ref->{rolename} =~ s/_/ /gr;

        print "Found After Processing: $role_name -> '$role_desc'\n\n";
        push(@tex_array, "\\item [$role_name] \\htmlspacing $role_desc \\index{$index}");
    }
    push(@tex_array, description_epilog());
    write_file( join ("\n", @tex_array), $file_name);
}

#------------
# Main
#------------
print "Example Usage:\n";
print "  PGHOSTADDR='172.16.1.218' PGPORT='5001' PGDATABASE='example_inc' PGUSER='postgres' PGPASSWORD='abc' perl gather-db-info.pl\n";

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
        ReadOnly => 1,
        PrintError => 1,
        RaiseError =>  1 })
    or die "Unable to connect: $DBI::errstr\n";

print "Connected to the '$dbh->{pg_db}' database.\n";
if ($dbh->{pg_db} eq 'postgres') {
    die "This code must connect to an LSMB company database, not the postgres database.\n";
}

get_format_role_comments('role_list_appendex.tex', $dbh);

# Done, clean up
$dbh->disconnect();
