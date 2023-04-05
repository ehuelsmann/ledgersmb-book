# LedgerSMB Book

For LedgerSMB Small and Medium business accounting and ERP

# DESCRIPTION

The LedgerSMB Book is the documentation for the open source [LedgerSMB](https://ledgersmb.org) small and medium business accounting and ERP system.

The source for the LedgerSMB accounting system can be found on [github](https://github.com/ledgersmb/LedgerSMB).

The source for the LedgerSMB Book can be found on [github](https://github.com/ehuelsmann/ledgersmb-book).

# Build Requirements

The book should build with any recent LaTeX installation. The book is expected to produce both HTML and PDF. The book is currently tested with:

* LaTeXML version 0.8.6
* TeX Live 2022

All documents can be built by running the script `local-build.sh --use-pdf-latex`. This will create a directory called `local-build` that contains the book in PDF, single page HTML, and multi-page HTML formats.

The Book also builds in PDF format without using the `local-build.sh` script using: 

* TeXstudio version 4.5.1 or later
* TeXShop version Version 5.12 or later

The first time the book is built in a clean repository using TeXstudio or TeXShop the glossary build may error out or not be included into the PDF. Just build again and it will fix itself.

# Development Requirements

Since the build process uses LaTeXML the only packages that can be in the LaTeX source are those compatible with LaTeXML.  The acceptable package list can be found at [LaTeXML Bindings](https://math.nist.gov/~BMiller/LaTeXML/manual/included.bindings/).

