# soak-cobble-riot

Import a library from [Apple Books] into [calibre], possibly repeatedly

[Apple Books]: https://www.apple.com/apple-books/
[calibre]: https://calibre-ebook.com/

# Prerequisites

Install [calibre] to manage a library of electronic books.

Install necessary prerequisites from [CPAN], via [cpan] or [cpanm].

[CPAN]: https://www.cpan.org/
[cpan]: https://metacpan.org/pod/CPAN
[cpanm]: https://metacpan.org/pod/App::cpanminus

- [Data::Plist::BinaryReader]
- [JSON]
- [Log::Log4perl]
- [LWP::UserAgent]
- [String::ShellQuote]
- [URI]

[Data::Plist::BinaryReader]: https://metacpan.org/pod/Data::Plist::BinaryReader
[JSON]: https://metacpan.org/pod/JSON
[Log::Log4perl]: https://metacpan.org/pod/Log::Log4perl
[LWP::UserAgent]: https://metacpan.org/pod/LWP::UserAgent]
[String::ShellQuote]: https://metacpan.org/pod/String::ShellQuote
[URI]: https://metacpan.org/pod/URI

# Usage

Start the [calibre content server].  (I chose port 8081 because the default 8080 is already taken on my machine.)

[calibre content server]: https://manual.calibre-ebook.com/#the-calibre-content-server

```sh
calibre-server --port 8081
```

Scan your library for books to import, generating a script.

```sh
perl ./books2calibre.pl > books2calibre.sh
```

Stop the calibre content server.

Run the import script.

```sh
sh ./books2calibre.sh
```

Start the calibre user interface and browse your books.

# License

[Artistic License 2.0] governs copying, modification, and (re)distribution of this software.  See also [LICENSE.txt].

[Artistic License 2.0]: https://www.perlfoundation.org/artistic-license-20.html
[LICENSE.txt]: LICENSE.txt

