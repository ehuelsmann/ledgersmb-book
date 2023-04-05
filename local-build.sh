#!/bin/sh

# For local build and testing
set -e 

base_path=.
img_path=$base_path/images
dest_path=$base_path/local-build
tmp_path=/tmp

mkdir -p $dest_path
cd $base_path

if [[ $1 = '--use-pdf-latex' ]]; then

    # Set the stage for building the glossaries
    pdflatex -file-line-error master.tex
    # Build the glossaries
    makeglossaries master
    # Update the links.
    pdflatex -file-line-error master.tex

elif [[ $1 = '--use-latex-mk' ]]; then

    # Make PDF
    # Not able to get latexmk to process glossaries correctly right now.
    latexmk -dvi- \
        -gg \
        -interaction=nonstopmode \
        -pdf \
        -silent \
        -pdflatex \
        # -aux-directory=${tmp_path} \
        # -output-directory=${base_path}
        master.tex

else

    # Check for help or no args to provide help.
    echo "Required options to $0 are one of:"
    echo "  --help"
    echo "  --use-pdf-latex"
    echo "  --use-latex-mk # FIXME: Not working right now."
    if [[ $1 != '--help' ]]; then
        echo "One arg must be specified."
        exit 1
    fi
    exit 0

fi

echo 'Make XML'
latexml --inputencoding=utf-8 \
        --path=$img_path/ \
        --destination=book.xml \
        --verbose \
        $base_path/master.tex

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

# move the pdf so it does not get cleaned up
mv master.pdf ${dest_path}


# echo 'Clean up the latex files'
# This means everything will be rebuild from scratch next time.
# Probably a better way to do this like moving the aux files to /tmp.
# latexmk -C


echo "The full book can be found at: $dest_path/full-book/index.html"
echo "The split book can be found at: $dest_path/split-book/index.html"
echo "The pdf can be found at: $dest_path/master.pdf"

exit 0
