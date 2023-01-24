use strict;
use HTTP::Daemon;
use HTTP::Status;
use feature 'state';

use constant CHUNKSIZE    => 255;

$SIG{PIPE} = 'IGNORE'; # prevent perl from quitting if trying to write to a closed socket ???

my $d = HTTP::Daemon->new(
	LocalPort => 9999,
	ReuseAddr => 1,
	Timeout => 3
) || die;


print get_mime_type("asdf.kek/kek.txt"), "\n";
print "starting metaclip server ...\n";
print "<URL:", $d->url, ">\n";

my $clipboard_data;
my $clipboard_type;

while(1) {
    my $c = $d->accept || next;
    my $req = $c->get_request;
    unless(defined $req){
		$c->close;
    		undef($c);
		next;
    }
    
    my $res = get_response($req);
    $c->force_last_request;
    if ($res) {
		if(%{$res->headers}{"transfer-encoding"} eq "chunked"){
			send_response_chunked($c, $res);
		}
		else{
			delete ${$res->headers}{"transfer-encoding"};
			$c->send_response($res);
		}
    }
    else{
		$c->send_response(status_message_res(500));
    }
    $c->close;
    undef($c);
}

sub send_response_chunked{
	my ($c, $res) = @_;

	$c->send_status_line($res->code);
	foreach my $key (keys %{$res->headers}){
		$c->send_header(%{$res->headers}{$key});
	}
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

	if($req->uri->path eq '/'){
		return HTTP::Response->new(200, undef, ["transfer-encoding" => "chunked", "Content-Type" => "text/html"], read_static_file("/static/index.html"));
	}

	# GET /static/*
	if($req->uri->path =~ /^\/static\// and $req->method eq 'GET'){
		my $data = read_static_file($req->uri->path);
		return status_message_res(404) unless $data;
		my $mimetype = get_mime_type($req->uri->path);
		my @header;
		push @header, "transfer-encoding" => "chunked";
		push @header, "Content-Type" => $mimetype if $mimetype;
		return HTTP::Response->new(200, undef, \@header, $data);
	}

	# * /ping
	if($req->uri->path eq '/ping'){
		return HTTP::Response->new(200, undef, undef, "pong");
	}

	# * /clip
	if($req->uri->path eq '/clip'){
		# GET /clip
		if($req->method eq 'GET'){
			unless($clipboard_data){
				return status_message_res(204); # 204 empty response!
			}
			my @header;
			push @header, "transfer-encoding" => "chunked";
			push @header, "content-type" => $clipboard_type if $clipboard_type;
			return HTTP::Response->new(200, undef, \@header, $clipboard_data);
		}

		# POST /clip
		if($req->method eq 'POST' or $req->method eq 'PUT'){
			$clipboard_data = $req->content || undef;
			$clipboard_type = $req->header("Content-Type") || undef;
			$clipboard_type = undef unless $clipboard_data;
			return status_message_res(200);
		}

		# DELETE /clip
		if($req->method eq 'DELETE'){
			$clipboard_data = undef;
			$clipboard_type = undef;
			print "clear!\n";
			return status_message_res(200);
		}
	}
	return status_message_res(404);
}

sub status_message_res{
	my $code = shift;
	my $message = status_message($code);
	return HTTP::Response->new($code, undef, undef, "$code - $message");
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