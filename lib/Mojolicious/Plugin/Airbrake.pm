package Mojolicious::Plugin::Airbrake;

use 5.010001;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;
use Data::Dumper;

our $VERSION = '0.01';

has 'api_key';
has 'airbrake_base_url' => 'https://airbrake.io/api/v3/projects/';
has 'ua' => sub { Mojo::UserAgent->new() };
has 'project_id';
has 'pending_exceptions' => sub { {} };

has url => sub {
  my $self = shift;

  return $self->airbrake_base_url . $self->project_id . '/notices?key=' . $self->api_key;
};

has user_id_sub_ref => sub {
  return 'n/a';
};

sub register {
  my ($self, $app, $conf) = (@_);
  $conf ||= {};

  $self->_hook_after_dispatch($app);
  $self->_hook_on_message($app);

}

sub _hook_after_dispatch {
  my $self = shift;
  my $app = shift;

  $app->hook(after_dispatch => sub {
    my $c = shift;

    if (my $ex = $c->stash('exception')) {
      # Mark this exception as handled. We don't delete it from $pending
      # because if the same exception is logged several times within a
      # 2-second period, we want the logger to ignore it.
      $self->pending->{$ex} = 0 if defined $self->pending->{$ex};
      $self->notify($ex, $c);
    }

  });

}

sub _hook_on_message {
  my $self = shift;
  my $app = shift;

  $app->log->on(message => sub {
      my ($log, $level, $ex) = @_;
      if ($level eq 'error') {
        $ex = Mojo::Exception->new($ex) unless ref $ex;
   
        # This exception is already pending
        return if defined $self->pending->{$ex};
   
        $self->pending->{$ex} = 1;
   
        # Wait 2 seconds before we handle it; if the exception happened in
        # a request we want the after_dispatch-hook to handle it instead.
        Mojo::IOLoop->timer(2 => sub {
          $self->notify($ex) if delete $self->pending->{$ex};
        });
      }

  });
}

sub notify {
  my ($self, $ex, $c) = @_;

  $self->ua->post($self->url => {'Content-Type' => 'application/json'} => $self->_json_content($ex, $c), sub {} );
}

sub _json_content {
  my $self = shift;
  my $ex = shift;
  my $c = shift;

  my $json = {
    notifier => {
      name => 'Mojolicious::Plugin::Airbrake',
      version => $VERSION,
      url => 'stackhaus.com'
    }
  };

  $json->{errors} = [
    type => ref $ex,
    message => $ex->message,
    backtrace => [],
  ];

  foreach my $frame (@{$ex->frames}) {
    my ($package, $file, $line, $subroutine) = @$frame;
    push @{$json->{errors}->{backtrace}}, {
      file => $file, line => $line, function => $subroutine
    };
  }

  $json->{context} = {
    environment => $c->app->mode,
    rootDirectory => $c->app->home,
    url => $c->req->url->to_abs,
    component => ref $c,
    action => $c->stash('action'),
    userId => $self->user_id_sub_ref()
  };

 $json->{environment} = { map { $_ => "".$c->req->headers->header($_) } (@{$c->req->headers->names}) };
 $json->{params} = { map { $_ => string_dump($c->stash('snapshot')->{$_})  } (keys %{$c->stash('snapshot')}) };
 $json->{session} = { map { $_ => string_dump($c->session($_))  } (keys %{$c->session}) };

}

sub string_dump {
  my $obj = shift;
  ref $obj ? Dumper($obj) : $obj;
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Mojolicious::Plugin::Airbrake

=head1 SYNOPSIS

  $self->plugin('Airbrake' => {
    key => "",
    url => ""
  });

=head1 DESCRIPTION


=head2 EXPORT

None by default.



=head1 SEE ALSO

Please see this PasteBin entry: http://pastebin.com/uaCS5q9w

=head1 AUTHOR

Jonathan Taylor, E<lt>jon@stackhaus.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Jonathan Taylor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
