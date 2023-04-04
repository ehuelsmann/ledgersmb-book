#!/bin/sh

# For local build and testing
set -e 

base_path=.
img_path=$base_path/images
dest_path=$base_path/local-build
tmp_path=/tmp

mkdir -p $dest_path
cd $base_path

# Set the stage for building the glossaries
pdflatex master.tex
# Build the glossaries
makeglossaries master
# Update the links.
pdflatex master.tex

# Make PDF
# Not able to get latexmk to process glossaries correctly right now.
# latexmk -dvi- \
#     # -c  \
#     -gg
#     -interaction=nonstopmode \
#     -pdf \
#     -silent \
#     # -aux-directory=${tmp_path} \
#     # -output-directory=${base_path}
#     master.tex

# Make HTML
latexml --inputencoding=utf-8 \
        --path=$img_path/ \
        --destination=book.xml \
        --verbose \
        $base_path/master.tex

# Found additional.css
# at https://book.ledgersmb.org/1.3/split-book/additional.css

rm -rf $tmp_path/split-book
mkdir -p $tmp_path/split-book
cp additional.css $tmp_path/split-book/additional.css
latexmlpost --destination=$tmp_path/split-book/index.html \
            --split \
            --splitnaming=label \
            --format=html \
            --css=$tmp_path/split-book/additional.css \
            --sitedirectory=$tmp_path/split-book/ \
            book.xml

rm -rf $tmp_path/full-book
mkdir -p $tmp_path/full-book
cp additional.css $tmp_path/full-book/additional.css
latexmlpost --destination=$tmp_path/full-book/index.html \
            --format=html \
            --css=$tmp_path/full-book/additional.css \
            --sitedirectory=$tmp_path/full-book/ \
            book.xml

for i in full-book split-book ; do
  # Remove all of the existing files.
  rm -rf $dest_path/$i
  # Copy the temp files to the destination.
  mv $tmp_path/$i $dest_path
done

# move the pdf so it does not get cleaned up
mv master.pdf ${dest_path}

# Clean up the latex files.
# This means everything will be rebuild from scratch next time.
# Probably a better way to do this.
latexmk -c

exit 0
