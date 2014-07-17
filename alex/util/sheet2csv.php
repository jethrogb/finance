<?php
# Jethro's finance tools
# Copyright (C) 2014  Jethro G. Beekman
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

function loc2coords($loc)
{
	preg_match('/^([A-Z])+([0-9]+)$/',$loc,$m);
	$x=array_reduce(str_split($m[1]),function($m,$v) { return ord($v)-ord('A')+($m*26); },0);
	$y=intval($m[2])-1;
	return array($x,$y);
}

$xml=simplexml_load_file($argv[1],null,LIBXML_NONET);
$xml->registerXPathNamespace('x','http://schemas.openxmlformats.org/spreadsheetml/2006/main');
$arr=array();
foreach ($xml->xpath('//x:row') as $row)
{
	$row->registerXPathNamespace('x','http://schemas.openxmlformats.org/spreadsheetml/2006/main');
	foreach ($row->xpath('x:c') as $cell)
	{
		$cell->registerXPathNamespace('x','http://schemas.openxmlformats.org/spreadsheetml/2006/main');

		list($x,$y)=loc2coords($cell['r']);

		$val='';
		foreach ($cell->xpath('x:is/x:t/text()') as $v) $val.=$v;
		foreach ($cell->xpath('x:v/text()') as $v) $val.=$v;

		if (!isset($arr[$y])) $arr[$y]=array();
		$arr[$y][$x]=$val;
	}
}

foreach ($arr as $row)
{
	echo implode(',',array_map(function($v) { return '"'.str_replace('"','""',$v).'"'; },$row)).PHP_EOL;
}
