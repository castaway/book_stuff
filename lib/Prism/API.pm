package Prism::API;

use strict;
use warnings;

use Moo;
use WWW::Mechanize;
use HTML::TreeBuilder;
use HTML::Microdata;
use Time::ParseDate;
use DateTime;

use Data::Dumper;

has 'login_uri' => ( is => 'ro', required => 1, default => sub { 
                   'https://capitadiscovery.co.uk/swindon/login'
                   });
has 'account_uri' => ( is => 'ro', required => 1, default => sub { 
                   'https://capitadiscovery.co.uk/swindon/account'
                   });
has 'history_uri' => ( is => 'ro', required => 1, default => sub { 
                   'https://capitadiscovery.co.uk/swindon/account/history'
                 });
has 'mech' => ( is => 'ro', required => 1);

sub login {
    my ($class, %args) = @_;
    my $number = $args{card_number};
    my $passw = $args{password};

    my $mech = WWW::Mechanize->new();
    my $self = $class->new({mech => $mech});
    $mech->get($self->login_uri);
    my $resp = $mech->submit_form(with_fields => { barcode => $number,
                                                   pin => $passw });

    $mech->get($self->account_uri);
#    print STDERR Dumper($resp);
    return $self;
}

sub loans {
    my ($self) = @_;

    if(!$self->mech || !$self->mech->uri) {
        die "Not logged in yet!";
    }
    $self->mech->get($self->account_uri);

    my $tree = HTML::TreeBuilder->new_from_content($self->mech->content);
#    $tree->dump;

    my @loans = $tree->look_down('id' => 'loans', '_tag' => 'table')
        ->look_down('_tag' => 'tbody')
        ->look_down('_tag' => 'tr');

    my @books;
    foreach my $row (@loans) {
        my $th = $row->look_down('_tag' => 'th');
        
        push @books, {
            %{ $self->_row_to_book($row) },
            due_date => $self->_get_date($th->right->as_text, 'PREFER_FUTURE'),
        };
    }

    return @books;
}

sub history {
    my ($self) = @_;

    if(!$self->mech || !$self->mech->uri) {
        die "Not logged in yet!";
    }
    $self->mech->get($self->history_uri);
    my $tree = HTML::TreeBuilder->new_from_content($self->mech->content);
#    $tree->dump;

    my @loans = $tree->look_down('id' => 'history', '_tag' => 'table')
        ->look_down('_tag' => 'tbody')
        ->look_down('_tag' => 'tr');

    my @books;
    foreach my $row (@loans) {
        my $th = $row->look_down('_tag' => 'th');

        my $book = {
            %{ $self->_row_to_book($row) },
            borrowed => $self->_get_date($th->right->as_text, 'PREFER_PAST'),
            returned => $self->_get_date($th->right->right->as_text, 'PREFER_PAST'),
        };
        $book->{microdata} = $self->item_id_to_microdata($book->{link});
        
        push @books, $book;
    }

    return @books;

}

=head2 item_id_to_microdata

Return a hashref of stuff based on an item id for an item in the library.

=cut

sub item_id_to_microdata {
  my ($self, $id) = @_;

  # deal with it if the id passed in is actually a fairly full url.
  $id =~ s/[^0-9]//g;

  $self->mech->get(URI->new_abs("items/$id", $self->login_uri));
  my $micro = HTML::Microdata->extract($self->mech->content)->items;

#   print STDERR Data::Dumper::Dumper($micro);

  return $micro->[0];

  # my $tree = HTML::TreeBuilder->new_from_content($self->mech->content);
  # #$tree->dump;
  # # <span itemprop="isbn">9780008138301</span>
  # my $ret = {};
  # for my $e ($tree->look_down(itemprop => qr/./)) {
  #     my $k = $e->attr('itemprop');
  #     my $v = $e->as_trimmed_text;
  #     print STDERR " $id {$k} = $v\n";
  #     push @{$ret->{$k}}, $v;
  # }
  # return $ret;
}


=head2 _row_to_book

Return a hashref of book name, author, link from an HTML::Element
object representing a TR row from the loans or history tables.

=cut

sub _row_to_book {
    my ($self, $row) = @_;

    my $th = $row->look_down('_tag' => 'th');
    my $link = $th->look_down('_tag' => 'a');
    my $img = $link->look_down('_tag' => 'img');
    my $author = $th->look_down('class' => 'author');
    ## We don't currently care when the author was born:
    $author = $author->as_text;
    $author =~ s/, \d{4}-$//;
    my $title = $img->right;
    $title =~ s/^\s+//;
    $title =~ s/\s+$//;

    return {
        link => URI->new_abs($link->attr('href'), $self->login_uri),
        image => URI->new_abs($img->attr('src'), $self->login_uri),
        title => $title,
        author => $author,
    };

}

sub _get_date {
    my ($self, $date_str, $prefer) = @_;

    print STDERR "String: $date_str\n";
    ## parsedate reads Month Day(st|nd|th|rd), we have Day(st|nd|th|rd) Month
    my ($day, $month, $year) = $date_str =~ /^(\d{1,2}\w{2})\s(\w+)\s?(?:\s(\d{4}))?$/;
    $year ||='';
    $date_str = "$month $day${year}";
    
    my ($date, $error) = parsedate($date_str, $prefer => 1, TIME_REQUIRED => 0);

    $date||='';
    $error ||='';
    print STDERR "$date_str $date, $error\n";

    return DateTime->from_epoch(epoch => $date, time_zone => 'Europe/London');
}


1;
