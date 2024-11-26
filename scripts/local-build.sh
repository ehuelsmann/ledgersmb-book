#!/bin/bash

# For local build and testing
set -e 

base_path=.
img_path=$base_path/images
dest_path=$base_path/scripts/local-build
tmp_path=/tmp

# Backup to the root directory for processing
cd ..

# Older versions of this script had this directory at the root,
# which is no longer used.
rm -rfv local-build

# Make sure the destination exists
mkdir -p $dest_path

if [[ $1 = '--use-pdf-latex' ]]; then

    # Builds everything needed or not
    
    # Set the stage for building the glossaries
    pdflatex -file-line-error ledgersmb-book.tex
    # Build the glossaries
    makeglossaries ledgersmb-book
    # Update the links.
    pdflatex -file-line-error ledgersmb-book.tex

elif [[ $1 = '--use-latex-mk' ]]; then

    # Only builds files that have changed
    # Have to use '-shell-escape' in order to build graphviz's dot files
    # latexmk takes 3 runs to complete as of 26 Nov 2024
    #    -diagnostics \
    latexmk -dvi- \
        -shell-escape \
        -interaction=nonstopmode \
        -pdf \
        -silent \
        ledgersmb-book.tex

else

    # Show help when one of --use-latex-mk or --use-pdf-latex is not provided.
    echo "Required options to $0 are one of:"
    echo "  --help"
    echo "  --use-pdf-latex (not recommended anymore)"
    echo "  --use-latex-mk"
    if [[ $1 != '--help' ]]; then
        echo "One arg must be specified."
        exit 1
    fi
    exit 0

fi

# move the pdf so it does not get cleaned up
mv ledgersmb-book.pdf ${dest_path}

echo 'Make XML'
latexml --inputencoding=utf-8 \
        --path=${base_path}/$img_path/ \
        --destination=book.xml \
        --verbose \
        $base_path/ledgersmb-book.tex

# Found additional.css
# at https://book.ledgersmb.org/1.3/split-book/additional.css

echo 'Make Split-Book HTML'
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

echo 'Make Full-Book HTML'
rm -rf $tmp_path/full-book
mkdir -p $tmp_path/full-book
cp additional.css $tmp_path/full-book/additional.css
latexmlpost --destination=$tmp_path/full-book/index.html \
            --format=html \
            --css=$tmp_path/full-book/additional.css \
            --sitedirectory=$tmp_path/full-book/ \
            book.xml

echo 'Move tmp files to ${dest_path}'
for i in full-book split-book ; do
  # Remove all of the existing files.
  rm -rf $dest_path/$i
  # Copy the temp files to the destination.
  mv $tmp_path/$i $dest_path
done

# echo 'Clean up the latex files'
# This means everything will be rebuilt from scratch next time.
# latexmk -C

echo "The full book can be found at: $dest_path/full-book/index.html"
echo "The split book can be found at: $dest_path/split-book/index.html"
echo "The pdf can be found at: $dest_path/ledgersmb-book.pdf"

exit 0
