# LedgerSMB Book Development Notes

Collected notes about development in this repository.

## Experimenting with alternative converters to HTML

### LaTeXML

LaTeXML version 0.8.7 has problems with TeX Live 2023. The conversion hangs. The problem is known at LaTeXML upstream, but as of 19 Nov 2023 no solution has been released.

[Issue 2109](https://github.com/brucemiller/LaTeXML/pull/2109)

[Issue 2151](https://github.com/brucemiller/LaTeXML/pull/2151)

[Issue 2064](https://github.com/brucemiller/LaTeXML/issues/2064)

[Issue 2124](https://github.com/brucemiller/LaTeXML/issues/2124)

Fixes have been merged, waiting on release.

### hevea (19 Nove 2023)

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

### LaTeX2HTML (19 Nove 2023)

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
