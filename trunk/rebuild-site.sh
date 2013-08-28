#!/bin/sh

base_path=/www/vhosts/book.ledgersmb.org/book-build
img_path=$base_path/images
dest_path=/www/vhosts/book.ledgersmb.org/public_html/1.3
tmp_path=/www/vhosts/book.ledgersmb.org/tmp


export PATH=/usr/local/bin:$PATH

cd $base_path

latexml --inputencoding=utf-8 \
        --path=$img_path/ \
        --destination=book.xml \
        $base_path/master.tex

rm -rf $tmp_path/split-book
mkdir -p $tmp_path/split-book
cp $dest_path/split-book/additional.css $tmp_path/split-book/additional.css
latexmlpost --destination=$tmp_path/split-book/index.html \
            --split \
            --splitnaming=label \
            --format=html \
            --css=$tmp_path/split-book/additional.css \
            --sitedirectory=$tmp_path/split-book/ \
            book.xml

rm -rf $tmp_path/full-book
mkdir -p $tmp_path/full-book
cp $dest_path/full-book/additional.css $tmp_path/full-book/additional.css
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
