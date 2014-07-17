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

$doc=new DOMDocument();
@$doc->loadHTMLFile($argv[1],LIBXML_NOERROR|LIBXML_NOWARNING|LIBXML_NONET);
$xml=simplexml_import_dom($doc);
foreach ($xml->xpath('//table/tr') as $row)
{
	$first=true;
	foreach ($row->xpath('td|th') as $cell)
	{
		if ($first)
			$first=false;
		else
			echo ',';

		echo '"'.str_replace(array('"',chr(10),chr(13)),array('""',' ',''),dom_import_simplexml($cell)->textContent).'"';

		for ($i=0;$i<(intval($cell['colspan'])-1);$i++) echo ',';
	}
	echo PHP_EOL;
}
