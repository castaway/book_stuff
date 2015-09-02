#!/usr/bin/perl

## capita-software - http://www.capita-software.co.uk/solutions/libraries/prism
use strict;
use warnings;

use lib 'lib';
use lib 'goodreads/lib';

use Prism::API;
use Config::General;
use WWW::Goodreads::API;

die "Missing config file" if !-e "book_stuff.conf";

my $conf = Config::General->new('book_stuff.conf');
my %config = $conf->getall();


my $prism = Prism::API->login(
    %{ $config{'Prism::API'} },
);

## current loans:
# my @books = $prism->loans();
# print STDERR Data::Dumper::Dumper(\@books);

# first page of historical loans
my @history = $prism->history;
# print STDERR Data::Dumper::Dumper(\@history);

my $gr_api = WWW::Goodreads::API->new(
    %{ $config{'WWW::Goodreads::API'} },
);

## User check:
my $gr_user = $gr_api->call_method('auth_user');
# print STDERR Data::Dumper::Dumper($gr_user);
# print STDERR "User's books :", Data::Dumper::Dumper($gr_api->call_method('review.list', {
#     id => $gr_user->{user}{id},
#     shelf => 'read',
#                                                                          }));

foreach my $book (@history) {
## Find book
    
    my $id = $gr_api->call_method('isbn_to_book', { isbn => $book->{microdata}{properties}{isbn}[0] });
    next if !$id || $id =~ /\D/;

#    print STDERR "book id: $id\n";
    my $user_check = $gr_api->call_method('show_by_user_and_book', {
        user_id => $gr_user->{user}{id},
        book_id => $id,
                                          });

#    print STDERR Data::Dumper::Dumper($user_check);
    if(!$user_check->{review}) {
        ## No review, create from scratch:
        my $res = $gr_api->call_method('review.create',
                                       {
                                           book_id => $id,
                                           'review[read_at]' => $book->{returned}->ymd,
                                       }
            );
#        print STDERR "Created review: ", Data::Dumper::Dumper($res);
    } elsif($user_check->{review} && 
            !$user_check->{review}{read_at}) {
        ## Review exists but no date set, update:
        my $res = $gr_api->call_method('review.edit',
                                       {
                                           '_id' => $$user_check->{review}{id},
                                           'review[read_at]' => $book->{returned}->ymd,
                                       }
            );
#        print STDERR "Created review: ", Data::Dumper::Dumper($res);
    } else {
#        print STDERR "Already got that one\n";
    }


}
