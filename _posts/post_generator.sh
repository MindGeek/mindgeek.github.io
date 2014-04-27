#!/bin/bash

dater=$(date +"%Y-%m-%d")
title=$@

if [[ "" == "$title" ]]
then
	echo "no title"
	exit 1
fi

read -d '' header <<__msg
---
layout: post
title: "$title"
description: ""
category:
tags: [mind,geek]
---
{% include JB/setup %}
__msg

post_title=$(echo $title | tr ' ' '-')

post_name="${dater}-${post_title}.md"
echo "$header" > $post_name

vim $post_name




