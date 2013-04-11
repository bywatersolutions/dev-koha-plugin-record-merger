package Koha::Plugin::Com::ByWaterSolutions::RecordMerger;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use File::Basename;
use DateTime;
use Text::CSV;
use MARC::Record;
use MARC::Field;

use C4::Context;
use C4::Biblio;
use C4::Items;
use C4::Reserves;
use C4::Serials;

use open qw(:utf8);

## Here we set our plugin version
our $VERSION = 2.00;

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name   => 'Record Merger',
    author => 'Kyle M Hall',
    description =>
'This plugin takes a CSV file of biblionumbers and merges all records in a row into the record specified in the first column',
    date_authored   => '2015-07-01',
    date_updated    => '2015-07-01',
    minimum_version => '3.18',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'tool' subroutine means the plugin is capable
## of running a tool. The difference between a tool and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a tool
sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('uploaded_file') ) {
        $self->tool_step1();
    }
    else {
        $self->tool_step2();
    }

}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

sub tool_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'tool-step1.tt' } );

    print $cgi->header();
    print $template->output();
}

sub tool_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $dbh = C4::Context->dbh();
    print "Creating temporary table, populating with normalized data.\n";
    $dbh->do("DROP TABLE IF EXISTS temp_dedupe;");
    $dbh->do(
        q{
            CREATE TABLE temp_dedupe (
                entry_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
                biblionumber int(11) NOT NULL,
                normal_data varchar(255) NOT NULL,
                KEY normal_data (normal_data)
            ) ENGINE=InnoDB CHARSET=utf8;
        }
    );
    my $insert_sth = $dbh->prepare("INSERT INTO temp_dedupe (biblionumber,normal_data) VALUES (?,?)");
    my $sth        = $dbh->prepare("SELECT biblionumber FROM biblioitems");
    my $marc_sth   = $dbh->prepare("SELECT marc FROM biblioitems WHERE biblionumber=?");
    my $entry_sth  = $dbh->prepare("SELECT author,title FROM biblio where biblionumber=?");

    my $output;

  ROW: while ( my $row = $csv->getline($infh) ) {
        my $data = $row->[0];

        for my $bibnum (@$row) {
            $i++;
            print ".";
            print "\r$i" unless ( $i % 100 );
            $entry_sth->execute($bibnum);
            if ( !$entry_sth->fetchrow_array ) {
                if ( $bibnum eq $data ) {
                    $output->{$bib "$bibnum: Master biblio does not exist! Cannot merge.\n";
                    $field_not_present++;
                    next ROW;
                }
                else {
                    print "$bibnum: Child biblio does not exist.\n";
                    next;
                }
            }
            $inserted++;
            $insert_sth->execute( $bibnum, $data );
        }
    }

    print "\n$i records read from file.\n$inserted lines inserted to dedupe table.\n";
    print "$field_not_present master records were missing.\n\n";

    my $filename = $cgi->param("uploaded_file");
    my ( $name, $path, $extension ) = fileparse( $filename, '.csv' );

    my $upload_dir = '/tmp';
    my $infh       = $cgi->upload("uploaded_file");

    my $csv = Text::CSV->new( { binary => 1 } )
      or die "Cannot use CSV: " . Text::CSV->error_diag();

    my $template = $self->get_template( { file => 'tool-step2.tt' } );

    print $cgi->header();
    print $template->output();
}

1;
