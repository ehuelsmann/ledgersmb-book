# LedgerSMB Book Development Notes

Collected notes about development in this repository.

## Local Test Environment

Using `ubuntu-22.04.3-live-server-amd64.iso` as the base run the following:

```bash 
#!/bin/bash
set -e
set -x

# Setup Ubuntu to make LSMB Book 
sudo apt update
sudo apt -y upgrade

# From the book github action, which should always be consulted for changes.
# https://github.com/ehuelsmann/ledgersmb-book/blob/master/.github/workflows/typeset.yml
sudo apt-get install -y gcc make cpanminus libxslt1-dev libxml-libxml-perl 
sudo apt-get install -y texlive-latex-extra texlive-fonts-recommended libxml-perl latexml
sudo cpanm --notest LaTeXML

# For local-build.sh
sudo apt-get install -y latexmk

# For `gather-db-info.pl`
sudo apt-get install -y libdbi-perl libdbd-pg-perl 

# For `get-screen-shots.pl`
sudo apt-get install -y libtest-www-selenium-perl

git clone https://github.com/neilt/ledgersmb-book.git
				
sudo shutdown -r now
```

## Experimenting with alternative converters to HTML

See [https://texfaq.org/FAQ-LaTeX2HTML](https://texfaq.org/FAQ-LaTeX2HTML)

### TeX4ht

Not tested.

### LaTeXML

LaTeXML version 0.8.7 has problems with TeX Live 2023. The conversion hangs. The problem is known at LaTeXML upstream, but as of 9 March 2024 no solution has been released.

[Issue 2064](https://github.com/brucemiller/LaTeXML/issues/2064)

[Issue 2109](https://github.com/brucemiller/LaTeXML/pull/2109)

[Issue 2124](https://github.com/brucemiller/LaTeXML/issues/2124)

[Issue 2151](https://github.com/brucemiller/LaTeXML/pull/2151)

Fixes have been merged, waiting on release. Release 0.8.8 did not complely fix the problem for LSMB.  Still takes a long time to run?

### lwarp

lwarp does not handle items like:

```
\begin{description}[style=nextline]
\item[Balance Sheet] Provides a snapshot of the .....
\end{description}
```
Does seem to work when when `style=standard`.

Multipage HTML not working.

### LaTeX2HTML (19 Nov 2023)

[Github Source](https://github.com/latex2html/latex2html)

[Home Page CTAN](https://www.ctan.org/pkg/latex2html)

[Home Page](https://www.latex2html.org)

```bash
latex2html -help
perldoc latex2html

LaTeX2HTML ledgersmb-book.tex

*********** WARNINGS ***********  
No implementation found for style `lmodern'
No implementation found for style `url'
No implementation found for style `palatino'
No implementation found for style `enumitem'
No implementation found for style `makecell'
No implementation found for style `glossaries'
No implementation found for style `metalogo'

Substitution of arg to newlabelxx delayed.

? brace missing for \oldnewlabel

Unknown commands: acrshort footref printglossary setlist makecell else makeglossaries protected_at_file_at_percent LaTeXML ifdefined protected cleardoublepage fi ifpdf bullet XeLaTeX newacronym glspl newglossaryentry gls hypersetup 
Done.

```

### hevea (19 Nov 2023)

[Github Source](https://github.com/maranget/hevea)

[Home Page](https://hevea.inria.fr)

```bash
hevea ledgersmb-book.tex

./ledgersmb-book.tex:38: Warning: Command not found: \setlist
./ledgersmb-book.tex:66: Warning: Command not found: \makeglossaries
./ledgersmb-book.tex:68: Warning: Command not found: \ifdefined
./ledgersmb-book.tex:68: Warning: Command not found: \LaTeXML
./acronyms.tex:5: Warning: Command not found: \newacronym
./acronyms.tex:6: Warning: Command not found: \newacronym
./acronyms.tex:7: Warning: Command not found: \newacronym
./acronyms.tex:8: Warning: Command not found: \newacronym
./acronyms.tex:9: Warning: Command not found: \newacronym
./acronyms.tex:10: Warning: Command not found: \newacronym
./acronyms.tex:11: Warning: Command not found: \newacronym
./acronyms.tex:12: Warning: Command not found: \newacronym
./acronyms.tex:13: Warning: Command not found: \newacronym
./acronyms.tex:14: Warning: Command not found: \newacronym
./acronyms.tex:15: Warning: Command not found: \newacronym
./acronyms.tex:16: Warning: Command not found: \newacronym
./acronyms.tex:17: Warning: Command not found: \newacronym
./acronyms.tex:18: Warning: Command not found: \newacronym
./acronyms.tex:19: Warning: Command not found: \newacronym
./acronyms.tex:20: Warning: Command not found: \newacronym
./acronyms.tex:21: Warning: Command not found: \newacronym
./acronyms.tex:22: Warning: Command not found: \newacronym
./acronyms.tex:23: Warning: Command not found: \newacronym
./acronyms.tex:24: Warning: Command not found: \newacronym
./ledgersmb-book.tex:97: Giving up command: \include
./acronyms.tex:24: Error while reading LaTeX:
	Non-ascii '?' in input, consider using package inputenc
Adios

```

### TtH

However the resulting HTML does not really reach modern standards, and only very simple mathematics can be converted.

### plasTeX

Python based, not interested in adding python as a project requirement.

### TeXpider

Commercial, does not fit open source model