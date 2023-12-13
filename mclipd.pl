use HTTP::Server::PSGI;
use HTML::Template;

use JSON;

use constant PORT => 5000;
use constant HOST => "127.0.0.1";
use constant CHUNKSIZE => 1200;

use constant MIME_EMBEDABLE => [
	"text/plain",
	"application/json",
	"text/csv",
	"text/css"
];

my $server = HTTP::Server::PSGI->new(
    host => HOST,
    port => PORT,
    timeout => 120
);

$server->run(\&app);

my $INFO;    # ref to hash containing info about the clipped file
my $CONTENT; # array ref of chunked content of clipped file

sub app {
	my $env = shift;
	die "not suitable for multithreading/forking!\n" if $env->{"psgi.multithread"} or $env->{"psgi.multiprocess"};
	print $env->{REQUEST_METHOD}, " - ", $env->{PATH_INFO}, "\n";

	my $res;
	eval {
		$res = get_response($env);
	};
	if($@) {
		print "#ERROR: $@";
		return res_status_message(500);
	}

	return $res;
}

sub get_response {
	my $env = shift;

	if($env->{PATH_INFO} eq '/'){
		return res_temp_redirect('/ui');
	}

	if($env->{PATH_INFO} eq '/ui'){
		my $embed = undef;
		$embed = $CONTENT->[0] if $INFO->{embed};
		my (undef,$min,$hour,$mday,$mon,$year) = localtime $INFO->{time};
		return res_template("ui.html", {
			filename => $INFO->{filename} || $INFO->{time},
			time     => sprintf("%02d-%02d-%02d %02d:%02d", $year+1900, $mon, $mday, $hour, $min),
			embed    => $embed,
			size     => format_size($INFO->{length}),
			etag     => $INFO->{etag}
		});
	}

	if($env->{PATH_INFO} eq '/ui/upload/text'){
		return res_template("uptext.html", { etag => $INFO->{etag} });
	}

	if($env->{PATH_INFO} eq '/ui/upload/file'){
		return res_template("upfile.html", { etag => $INFO->{etag} });
	}

	if($env->{PATH_INFO} eq '/style') {
		return res_file("./style.css");
	}

	if($env->{PATH_INFO} eq '/favicon.ico') {
		return res_file("./favicon.ico");
	}

	if($env->{PATH_INFO} eq '/info'){
		return [200, [], [encode_json $INFO]];
	}

	if($env->{PATH_INFO} eq '/data'){
		# GET HEAD /data
		if($env->{REQUEST_METHOD} eq 'GET' or $env->{REQUEST_METHOD} eq 'HEAD'){
			return res_no_content() unless $CONTENT;

			if($env->{QUERY_STRING}){
				unless($env->{QUERY_STRING} eq $INFO->{etag}){
					return res_no_content();
				}
			}
			
			my $header = [
				"content-type"        => $INFO->{mimetype},
				"cache-control"       => "no-cache",
				"content-length"      => $INFO->{length},
				"etag"                => $INFO->{etag},
				"content-disposition" => ($env->{QUERY_STRING} eq "attachment" ? "attachment" : "inline")."; filename=\"".$INFO->{filename}."\""
			];
			return [200, $header, $env->{REQUEST_METHOD} eq 'HEAD' ? [] : $CONTENT];
		}

		# POST /
		if($env->{REQUEST_METHOD} eq "POST"){
			my $filename;
			if(my $header = $env->{HTTP_CONTENT_DISPOSITION}){
				($filename) = $header =~ /\bfilename=\"(.+)\"/; # extract filename
				$filename =~ s/[^a-zA-Z0-9_.-]/_/g; # replace funny characters with _
			}
			
			my $mime = $env->{CONTENT_TYPE} || "application/octet-stream";

			my ($length, $chunks) = chop_stream($env->{"psgi.input"}, CHUNKSIZE);
			return res_status_message(400) unless $length;
			my $time = time();
			$CONTENT = $chunks;
			$INFO = {
				time     => $time,
				filename => $filename || $time,
				mimetype => $mime,
				length   => $length,
				embed    => (is_mime_embedable($mime) and @$CONTENT == 1 and is_plaintext($CONTENT->[0])),
				etag     => $time
			};
			return res_status_message(200);
		}

		# DELETE /
		if($env->{REQUEST_METHOD} eq 'DELETE'){
			$INFO = undef;
			$CONTENT = undef;
			return res_status_message(200);
		}
	}

	return res_status_message(404);
}

sub is_plaintext {
	my $chunk = shift;
	return undef if($chunk =~ /[^ -~\t\r\n]/);
	return 1;
}

sub is_mime_embedable {
	my $mime = shift;
	my $embedable = MIME_EMBEDABLE;
	return 1 if grep( /^$mime$/, @$embedable);
	return undef;
}

sub format_size {
	my $str = (shift || 0)."b";
	my $units = ["kb", "mb", "gb", "tb", "pb"];
	my $lu = "b";
	foreach(@$units){
		last unless $str =~ s/(?<=\d)\d\d\d$lu$/$_/;
		$lu = $_;
	}
	return $str;
}

sub chop_stream {
	my $fh = shift;
	my $chunksize = shift || 2048;
	my @chunks;
	my $length = 0;
	while(1){
		my $chunk;
		my $l = read $fh, $chunk, $chunksize;
		last unless $l;
		$length = $length + $l;
		push @chunks, $chunk;
	}
	return $length, \@chunks;
}

sub res_temp_redirect {
	my $location = shift;
	return [307, ["Location" => $location], []];
}

sub res_status_message {
	my $code = shift;
	my $message = {
		200 => "ok",
		404 => "not found",
		400 => "bad request",
		500 => "internal server error :["
	}->{"$code"};
	unless($message){
		$message = shift || "";
	} 
	return [$code, ["content-type" => "text/plain"], ["$code - $message"]];
}

sub res_ok {
	return [200, shift || [], shift || []];
}

sub res_no_content {
	print "res no content\n";
	return [204, [], []];
}

sub res_template {
	my $name = shift;
	my $args = shift;
	my $temp = HTML::Template->new(filename => "./templates/$name");
	$temp->param($args);
	return [200, ["content-type" => "text/html"], [$temp->output()]];
}

sub res_file {
	my $file = shift;
	return res_status_message(404) unless -e $file;
	open(my $fh, "<", $file) or die "cannot read file $file\n";
	my ($length, $chunks) = chop_stream($fh, CHUNKSIZE);
	close $fh;
	return [200, ['cache-control' => 'max-age=3600'], $chunks];
}