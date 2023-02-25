use strict;
use warnings;
use DBD::Pg qw(:pg_types);
use JSON;
use Google::ProtocolBuffers::Dynamic;
use FindBin;

my $pbtx_contract;
my $network_id;
my $proto;

sub pbtx_history_prepare
{
    my $args = shift;

    if( not defined($args->{'pbtx_contract'}) )
    {
        print STDERR "Error: pbtx_history_writer.pl requires --parg pbtx_contract=XXX\n";
        exit(1);
    }

    if( not defined($args->{'network_id'}) )
    {
        print STDERR "Error: pbtx_history_writer.pl requires --parg network_id=XXX\n";
        exit(1);
    }
    
    $pbtx_contract = $args->{'pbtx_contract'};
    $network_id = $args->{'network_id'};

    my $pbtx_proto_dir = $FindBin::Bin;
    $proto = Google::ProtocolBuffers::Dynamic->new($pbtx_proto_dir);
    $proto->map({ package => 'pbtx', prefix => 'PBTX' });
    
    my $dbh = $main::db->{'dbh'};

    $main::db->{'pbtx_transactions_ins'} =
        $dbh->prepare('INSERT INTO PBTX_TRANSACTIONS ' .
                      '(event_id, block_num, block_time, trx_id, actor, seqnum, transaction_type, raw_transaction) ' .
                      'VALUES (?,?,?,?,?,?,?,?)');

    $main::db->{'current_permission_upd'} =
        $dbh->prepare('INSERT INTO CURRENT_PERMISSION (actor, permission, last_modified) ' .
                      'VALUES (?,?,?) ' .
                      'ON CONFLICT(actor) DO UPDATE SET permission=?, last_modified=?');

    $main::db->{'permission_history_ins'} =
        $dbh->prepare('INSERT INTO PERMISSION_HISTORY (event_id, block_num, block_time, trx_id, is_active, actor, permission) ' .
                      'VALUES (?,?,?,?,?,?,?)');
    
    printf STDERR ("pbtx_history_writer.pl prepared\n");
}



sub pbtx_history_check_kvo
{
    my $kvo = shift;

    if( $kvo->{'code'} eq $pbtx_contract and $kvo->{'scope'} == $network_id )
    {
        return 1;
    }
    return 0;
}


sub pbtx_history_row
{
    my $added = shift;
    my $kvo = shift;
    my $block_num = shift;
    my $block_time = shift;

    if( $kvo->{'code'} eq $pbtx_contract and $kvo->{'scope'} == $network_id )
    {
    }
}



sub pbtx_history_block
{
    my $block_num = shift;
    my $last_irreversible = shift;

    if( $block_num > $last_irreversible )
    {
        die('pbtx_history_writer.pl requires irreversible-only mode in chronicle');
    }
}


push(@main::prepare_hooks, \&pbtx_history_prepare);
push(@main::check_kvo_hooks, \&pbtx_history_check_kvo);
push(@main::row_hooks, \&pbtx_history_row);
push(@main::block_hooks, \&pbtx_history_block);

1;
