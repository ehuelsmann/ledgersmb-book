# LedgerSMB Book

For LedgerSMB Small and Medium business accounting and ERP

# DESCRIPTION

The LedgerSMB Book is the documentation for the open source [LedgerSMB](https://ledgersmb.org) small and medium business accounting and ERP system.

The source for the LedgerSMB accounting system can be found on [github](https://github.com/ledgersmb/LedgerSMB).

The source for the LedgerSMB Book can be found on [github](https://github.com/ehuelsmann/ledgersmb-book).

# Build Requirements

The book should build with any recent LaTeX installation. The book is expected to produce both HTML and PDF and is currently tested with:

* LaTeXML version 0.8.7
* TeX Live 2022

All documents can be built locally by running the script `local-build.sh --use-pdf-latex`. This will create a directory called `local-build` that contains the book in PDF, single page HTML, and multi-page HTML formats.

The Book also builds in PDF format without using the `local-build.sh` script using: 

* TeXstudio version 4.5.1 or later
* TeXShop version Version 5.12 or later

The first time the book is built in a clean repository using TeXstudio or TeXShop the glossary or index build may error out or not be included into the PDF. This is normally fixed by making sure that TeXstudio or TeXShop are using `latexmk` instead of `pdflatex` for the build command.

# Development Requirements

Since the build process uses LaTeXML the only packages that can be in the LaTeX source are those compatible with LaTeXML.  The acceptable package list can be found at [LaTeXML Bindings](https://math.nist.gov/~BMiller/LaTeXML/manual/included.bindings/).

Note that as of LaTeXML version 0.8.7, the `enumitem` package style `nextline`  (`\setlist[description]{style=nextline}`), is not implemented. This book uses the following workaround to make the lists look good in the HTML files.

```
\ifpdf
      \newcommand{\htmlspacing}{}
\else
      \newcommand{\htmlspacing}{ \hfill \\}
\fi
```
Used as follows:

```
\begin{description}[style=nextline]
\item [ar\_transaction\_all]  \htmlspacing The item text.
\end{description}
```

Additional technical documentation which is useful when writing documentation can be found at:
[https://docs.ledgersmb.org](https://docs.ledgersmb.org)

# Scripts Directory

The directory `scripts` contains Perl scripts used to manually retrieve information from various sources for inclusion in the book.

To execute these scripts the following are required:

* Perl v5.34.1 or later - Earlier versions may work, but have not been tested
* Selenium::Firefox - Tested with version 1.49
* DBI - Tested with version 1.643 
* Access to a running LedgerSMB server with access to both the LSMB server and direct access to its database

On Ubuntu 22.10:

* libdbi-perl, libdbd-pg-perl
