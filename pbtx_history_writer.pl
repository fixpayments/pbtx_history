use strict;
use warnings;
use DBD::Pg qw(:pg_types);
use JSON;
use Google::ProtocolBuffers::Dynamic;

our @pbtx_transaction_hooks;


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
    $network_id = number2name($args->{'network_id'});

    my $pbtx_proto_dir = __FILE__;
    $pbtx_proto_dir =~ s/\/[a-z_.]+$//;
    $proto = Google::ProtocolBuffers::Dynamic->new($pbtx_proto_dir);
    $proto->load_file('pbtx.proto');
    $proto->map({ package => 'pbtx', prefix => 'PBTX' });

    my $dbh = $main::db->{'dbh'};

    $main::db->{'pbtx_transactions_ins'} =
        $dbh->prepare('INSERT INTO PBTX_TRANSACTIONS ' .
                      '(event_id, block_num, block_time, trx_id, actor, seqnum, transaction_type, raw_transaction) ' .
                      'VALUES (?,?,?,?,?,?,?,?)');

    $main::db->{'pbtx_transactions_getblock'} = $dbh->prepare('SELECT block_num FROM PBTX_TRANSACTIONS WHERE event_id=?');

    $main::db->{'pbtx_transactions_del'} = $dbh->prepare('DELETE FROM PBTX_TRANSACTIONS WHERE event_id=?');

    $main::db->{'current_permission_upd'} =
        $dbh->prepare('INSERT INTO CURRENT_PERMISSION (actor, permission, last_modified) ' .
                      'VALUES (?,?,?) ' .
                      'ON CONFLICT(actor) DO UPDATE SET permission=?, last_modified=?');

    $main::db->{'permission_history_ins'} =
        $dbh->prepare('INSERT INTO PERMISSION_HISTORY (event_id, block_num, block_time, trx_id, is_active, actor, permission) ' .
                      'VALUES (?,?,?,?,?,?,?)');

    $main::db->{'permission_history_getblock'} = $dbh->prepare('SELECT block_num FROM PERMISSION_HISTORY WHERE event_id=?');

    $main::db->{'permission_history_del'} = $dbh->prepare('DELETE FROM PERMISSION_HISTORY WHERE event_id=?');

    printf STDERR ("pbtx_history_writer.pl prepared. Using scope=%s\n", $network_id);
}



sub pbtx_history_check_kvo
{
    my $kvo = shift;

    if( $kvo->{'code'} eq $pbtx_contract and $kvo->{'scope'} eq $network_id and $kvo->{'table'} eq 'history' )
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

    if( $kvo->{'code'} eq $pbtx_contract and $kvo->{'scope'} eq $network_id and $kvo->{'table'} eq 'history' )
    {
        my $event_id = $kvo->{'value'}{'id'};
        my $event_type = $kvo->{'value'}{'event_type'};

        if( $added )
        {
            if( $event_type == 2 or $event_type == 3 ) # PBTX_HISTORY_EVENT_REGACTOR or PBTX_HISTORY_EVENT_UNREGACTOR
            {
                my $perm = PBTX::Permission->decode(pack('H*', $kvo->{'value'}{'data'}));

                $main::db->{'current_permission_upd'}->execute(
                    $perm->get_actor(), $kvo->{'value'}{'data'}, $block_time,
                    $kvo->{'value'}{'data'}, $block_time);

                $main::db->{'permission_history_ins'}->execute(
                    $event_id, $block_num, $block_time, $kvo->{'value'}{'trx_id'},
                    ($event_type == 2)?1:0, $perm->get_actor(), $kvo->{'value'}{'data'});
            }
            elsif( $event_type == 4 ) # PBTX_HISTORY_EVENT_EXECTRX
            {
                my $trx = PBTX::Transaction->decode(pack('H*', $kvo->{'value'}{'data'}));
                my $trxbody = PBTX::TransactionBody->decode($trx->get_body());

                $main::db->{'pbtx_transactions_ins'}->execute(
                    $event_id, $block_num, $block_time, $kvo->{'value'}{'trx_id'},
                    $trxbody->get_actor(), $trxbody->get_seqnum(), $trxbody->get_transaction_type(),
                    $kvo->{'value'}{'data'});

                foreach my $hook (@pbtx_transaction_hooks)
                {
                    &{$hook}($block_num, $block_time, $trxbody->get_actor(), $trxbody->get_seqnum(),
                             $trxbody->get_transaction_type(), $trxbody->get_transaction_content());
                }
            }
        }
        else
        {
            my $sth_type;
            if( $event_type == 2 or $event_type == 3 ) # PBTX_HISTORY_EVENT_REGACTOR or PBTX_HISTORY_EVENT_UNREGACTOR
            {
                $sth_type = 'permission_history';
            }
            elsif( $event_type == 4 ) # PBTX_HISTORY_EVENT_EXECTRX
            {
                $sth_type = 'pbtx_transactions';
            }

            if( defined($sth_type) )
            {
                $main::db->{$sth_type . '_getblock'}->execute($event_id);
                my $res = $main::db->{$sth_type . '_getblock'}->fetchall_arrayref();
                ## delete only if it is a fork
                if( scalar(@{$res}) > 0 and $res->[0][0] > $block_num - 200 )
                {
                    $main::db->{$sth_type . '_del'}->execute($event_id);
                }
            }
        }
    }
}





push(@main::prepare_hooks, \&pbtx_history_prepare);
push(@main::check_kvo_hooks, \&pbtx_history_check_kvo);
push(@main::row_hooks, \&pbtx_history_row);

1;
