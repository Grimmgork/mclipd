use strict;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Status qw(:constants);
use Bytes::Random::Secure qw( random_string_from );
use feature 'state';
use Time::Piece;
use MIME::Types;

use constant CHUNKSIZE	=> 255;
use constant APIKEY		=> "secretkey";
use constant MIMETYPES	=> MIME::Types->new;

$SIG{PIPE} = 'IGNORE'; # prevent perl from quitting if trying to write to a closed socket ???

my $d = HTTP::Daemon->new(
	LocalPort => 9999,
	ReuseAddr => 1,
	Timeout => 1
) || die;

print get_new_access_token(), "\n";
print localtime->strftime('%Y%m%d-%H%M%S'), "\n";

print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data;
my $clipboard_type;
my $clipboard_name;
my $clipboard_share = get_new_access_token();

while(1) {
    my $c = $d->accept || next;
    my $req = $c->get_request;
    unless(defined $req){
		$c->close;
    		undef($c);
		next;
    }
    
    my $res;
    eval{ $res = get_response($req) };
    if($@){
		print "$@\n";
		$res = status_message_res(500);
    }
    $c->force_last_request;
    send_response_chunked($c, $res);
    $c->close;
    undef($c);
}

sub send_response_chunked{
	my ($c, $res) = @_;
	my $cd = $res->code;
	$res->header("transfer-encoding" => "chunked");
	if($res->code == HTTP_NO_CONTENT){
		$res->remove_header("content-type");
		$res->remove_header("transfer-encoding");
	}
	$c->send_status_line($res->code);
	my @fieldnames = $res->header_field_names;
	foreach my $key (@fieldnames){
		$c->send_header($key, $res->header($key));
	}

	print $c "\n";
	return if $res->code == HTTP_NO_CONTENT;

	my $i = 0;
	while(my $chunk = substr $res->content, $i, CHUNKSIZE){
		my $hex = sprintf("%X", length $chunk);
		print $c $hex, "\n";
		print $c $chunk, "\n";
		$i += length $chunk;
	}
	print $c "0\n\n";
}

sub get_response{
	my ($req) = @_;
	print $req->method, " - ", $req->uri->path, "\n";
	my $authenticated = 1 if $req->header("apikey") eq APIKEY;

	# GET /static/*
	if($req->method eq 'GET' and $req->uri->path =~ /^\/static\//){
		return status_message_res(404) unless my $data = read_static_file($req->uri->path);
		my $mimetype = MIMETYPES->mimeTypeOf($req->uri->path);
		my @header;
		if($mimetype){
			push @header, "x-content-type-options" => "nosniff";
			push @header, "content-type" => $mimetype if $mimetype;
		}
		return HTTP::Response->new(200, undef, \@header, $data);
	}

	# GET /[secretlocation]/[file.txt]
	if($req->method eq 'GET' and my ($share, $filename) = $req->uri->path =~ m/^\/([^\/ ]+)\/([^\/ ]+)/){
		print "$share + $filename\n";
		return status_message_res(403) unless ($share eq $clipboard_share and $filename eq $clipboard_name);
		print "anonymous access granted!\n";
		$clipboard_share = get_new_access_token(); # move to a new safer location ~
		unless($clipboard_data){
			return status_message_res(204); # 204 empty response!
		}
		my $res = HTTP::Response->new(200, undef, undef, $clipboard_data);
		$res->header("content-type" => $clipboard_type, "x-content-type-options" => "nosniff") if $clipboard_type;
		return $res;
	}

	return status_message_res(403) unless $authenticated;

	# * /
	if($req->uri->path eq '/'){
		print "redirect\n";
		# GET /
		if($req->method eq 'GET'){
			return status_message_res(204) unless $clipboard_data; # 204 empty response! 
			return HTTP::Response->new(307, undef, ["location" => "/$clipboard_share/$clipboard_name"], undef);
		}
		# DELETE /
		if($req->method eq 'DELETE'){
			$clipboard_data = undef;
			$clipboard_type = undef;
			$clipboard_share = get_new_access_token(); # move to a new safer location ~
			print "cleared clipboard!\n";
			return status_message_res(200);
		}
	}

	# POST /[file.txt]
	if($req->method eq 'POST' and my($filename) = $req->uri =~ /^\/([^\/ ]+)$/){
		$clipboard_data = $req->content || undef;
		if($clipboard_data){
			$clipboard_type = MIMETYPES->type($req->header("content-type")) || undef;
			if($filename eq "undef"){
				my @exts = $clipboard_type->extensions;
				$filename = localtime->strftime('%Y%m%d-%H%M%S') . "." . $exts[0];
				print "$filename\n";
			}
			$clipboard_name = $filename;
		}
		$clipboard_share = get_new_access_token(); # move to a new safer location ~
		return status_message_res(200);
	}

	return status_message_res(404);
}

sub get_new_access_token{
	return random_string_from( 'abcdefghijklmnop123456789-', 10 );
}

sub status_message_res{
	my $code = shift;
	my $message = status_message($code);
	return HTTP::Response->new($code, undef, ["content-type" => "text/plain"], "$code - $message");
}

sub read_static_file{
	my ($filename) = @_;
	return undef unless $filename =~ /^\/static\//; # path must start with /static/*
	return undef if $filename =~ /\/\.+\//; # reject .. or . notation in path
	my @segments = split "/", $filename;
	@segments = grep { $_ ne '' } @segments; # remove empty segments
	$filename = join "/", ".", @segments; # construct real filename in file system
	return undef unless -f $filename;

	print "file access: $filename ...\n";
	open(my $fh, '<:raw', $filename) or die "Could not open file '$filename' $!";
	binmode $fh;
	my $data;
	while(<$fh>){
		$data = $data . $_;
	}
	close $fh;
	return $data;
}