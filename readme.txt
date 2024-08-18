# metaclip
a personal http clipboard in the cloud

mclipd.pl is a perl script implementing said clipboard.

note:
mclipd does not implement access control and thus should be run behind
an authentication/authorization reverse proxy when exposed over the internet.

mclipd is synchronous in nature and processes requests one after the other.
The goal is to keep all the clipped data in RAM.

The application is implementing the PSGI interface and is run by HTTP::Server::PSGI.

## endpoints:

GET    /data       downloads the stored file.
DELETE /data       clears the clipboard.
POST   /data       upload a file, filename is set by using "content-disposition: filename=file.f" header in the requests.

GET    /info       returns information about the clipped data in json format

GET    /ui         shows a simple ui, small text snippets will be embedded for convenient access.
GET    /ui/upload    shows a ui to upload content to the clipboard
