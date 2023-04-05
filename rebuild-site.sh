#!/bin/bash -xe

VHOSTS_PATH=${VHOSTS_PATH:-.}
base_path=$VHOSTS_PATH
img_path=$base_path/images/
dest_path=$VHOSTS_PATH/public_html
tmp_path=$VHOSTS_PATH/tmp


export PATH=/usr/local/bin:$PATH

cd $base_path
mkdir -p $dest_path $tmp_path

latexml --inputencoding=utf-8 \
        --path=$img_path/ \
        --destination=book.xml \
        $base_path/ledgersmb-book.tex

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
  rm -rf $dest_path/$i
  mv $tmp_path/$i $dest_path
done

exit 0
