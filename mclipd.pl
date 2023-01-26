use strict;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Status qw(:constants);
use feature 'state';

use constant CHUNKSIZE	=> 255;
use constant APIKEY		=> "secretkey";

$SIG{PIPE} = 'IGNORE'; # prevent perl from quitting if trying to write to a closed socket ???

my $d = HTTP::Daemon->new(
	LocalPort => 9999,
	ReuseAddr => 1,
	Timeout => 1
) || die;

print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data;
my $clipboard_type;
my $clipboard_name = "test.txt";
my $clipboard_share = "secretlocation";

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
	foreach my $key (keys %{$res->headers}){
		$c->send_header(%{$res->headers}{$key});
	}
	return if $res->code == HTTP_NO_CONTENT;

	print $c "\n";
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

	# GET /static/*
	if($req->uri->path =~ /^\/static\// and $req->method eq 'GET'){
		return status_message_res(404) unless my $data = read_static_file($req->uri->path);
		my $mimetype = get_mime_type($req->uri->path);
		my @header;
		if($mimetype){
			push @header, "x-content-type-options" => "nosniff";
			push @header, "content-type" => $mimetype if $mimetype;
		}
		return HTTP::Response->new(200, undef, \@header, $data);
	}

	# * /ping
	if($req->uri->path eq '/ping'){
		return HTTP::Response->new(200, undef, undef, "pong");
	}

	# * /
	if($req->uri->path eq '/'){
		# GET /
		if($req->method eq 'GET'){
			#unless($clipboard_data){
			#	return status_message_res(204); # 204 empty response!
			#}
			#my @header;
			#if($clipboard_type){
			#	push @header, "content-type" => $clipboard_type;
			#	push @header, "x-content-type-options" => "nosniff";
			#}
			#push @header, "content-disposition" => "inline; filename=$clipboard_name;" if $clipboard_name;
			#return HTTP::Response->new(200, undef, \@header, $clipboard_data);
			return HTTP::Response->new(307, undef, ["location" => "/$clipboard_share/$clipboard_name"], $clipboard_data);
		}
		# DELETE /
		if($req->method eq 'DELETE'){
			$clipboard_data = undef;
			$clipboard_type = undef;
			print "clear!\n";
			return status_message_res(200);
		}
	}

	# POST /[file.txt]
	if($req->method eq 'POST' and my($filename) = $req->uri =~ /^\/([^\/ ]+)$/){
		print "$filename\n";
		#$clipboard_data = $req->content || undef;
		#$clipboard_type = $req->header("content-type") || undef;
		#$clipboard_type = undef unless $clipboard_data;
		#chomp($clipboard_name = `cat /proc/sys/kernel/random/uuid`);
		return status_message_res(200);
	}


	# GET /[secret]/[file.txt]
	if($req->method eq 'GET' and my ($share, $filename) = $req->uri->path =~ m/^\/([^\/ ]+)\/([^\/ ]+)/){
		print "$share + $filename\n";
		unless ($share eq $clipboard_share and $filename eq $clipboard_name){
			return status_message_res(403);
		}
		print "authorized!\n";
		return status_message_res(200);
	}

	return status_message_res(404);
}

sub status_message_res{
	my $code = shift;
	my $message = status_message($code);
	return HTTP::Response->new($code, undef, ["content-type" => "text/plain"], "$code - $message");
}

sub get_mime_type{
	my $filename = shift;
	state %hash = (
        "html"	=> "text/html",
        "ico"	=> "image/vnd.microsoft.icon",
        "jpeg"	=> "image/jpeg",
        "png"	=> "image/png",
	   "txt"	=> "text/plain"
    );
    my ($ext) = $filename =~ /\.([^.]+)$/;
    return undef unless defined $ext;
    return $hash{$ext};
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