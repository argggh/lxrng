// Copyright (C) 2008, 2009 Arne Georg Gleditsch <lxr@linux.no>.
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
// The full GNU General Public License is included in this distribution
// in the file called COPYING.

function encode_lxrng(str) {
	return encodeURIComponent(str);
}

function decode_lxrng(str) {
	return str;
}

function popup_search(searchform) {
	searchform = document.getElementById(searchform);
	searchform.target = 'popup_' + window.name;
	searchform.navtarget.value = window.name;
	window.open('about:blank', 'popup_' + window.name,
		'resizable,width=400,height=600,menubar=yes,status=yes,scrollbars=yes');
	return true;
}

function popup_anchor() {
	var anchor = this;
	window.open('about:blank', 'popup_' + window.name,
		'resizable,width=400,height=600,location=no,menubar=yes,scrollbars=yes'); 

	anchor.target = 'popup_' + window.name;

	if (anchor.href.indexOf("navtarget=") >= 0)
		return true;

	if (anchor.href.indexOf("?") >= 0) {
		anchor.href = anchor.href + ';navtarget=' + window.name;
	}
	else {
		anchor.href = anchor.href + '?navtarget=' + window.name;
	}
	return true;
}

function navigate_here(searchform) {
	searchform = document.getElementById(searchform);
	searchform.target = window.name;
	return true;
}

function window_unique(serial) {
	if (!window.name)
		window.name = 'lxr_source_' + serial;
}

function do_search(form) {
	if (use_ajax_navigation) {
		var res = document.getElementById('search_results');
		res.style.display = 'block';
		res.innerHTML = '<div class="progress">Searching...</div>';
	
		pjx_search(['type__search',
			    'search', 'v', 'tree__' + loaded_tree, 'NO_CACHE'],
			   ['search_results']);
		return false;
	}
	else if (use_popup_navigation) {
		form.target = 'popup_' + window.name;
		form.navtarget.value = window.name;
		reswin = window.open('about:blank', 'popup_' + window.name,
			'resizable,width=400,height=600,location=no,menubar=yes,scrollbars=yes');
	}
	return true;
}

function hide_search() {
	var res = document.getElementById('search_results');
	res.style.display = 'none';
	return false;
}

var loaded_hash;
var loaded_tree;
var loaded_file;
var loaded_ver;

var pending_tree;
var pending_file;
var pending_ver;
var pending_line;

function ajax_nav() {
	var file = this.href.replace(/^(https?:.*?\/.*?[+][*]\/|)/, '');
	load_file(loaded_tree, file, loaded_ver, '');
	return false;
}

function ajax_jumpto_line() {
	location.hash = location.hash.replace(/\#L\d+$/, '') + 
		this.href.match(/\#L\d+$/);
	check_hash_navigation();	
	return false;
}

function ajax_prefs() {
	if (use_ajax_navigation) {
		var full_path = location.href.match(/(.*?)\/*#/)[1];
		full_path = full_path + '/' + loaded_tree;
		if (loaded_ver) {
			full_path = full_path + '+' + loaded_ver;
		}
		full_path = full_path + '/+prefs?return=' + loaded_file.replace(/^\/?$/, '.');
		location = full_path;
		return false;
	}
	else {
		return true;
	}
}

var hash_check;
function check_hash_navigation() {
	if (location.hash != loaded_hash) {
		if (location.hash.replace(/\#L\d+$/, '') == 
		    loaded_hash.replace(/\#L\d+$/, ''))
		{
			var l;
			if (location.hash.match(/\#(L\d+)/)) {
				l = RegExp.$1;
			}
			else {
				l = 'L1';
			}
			var a = document.getElementById(l);
			if (l && a) {
				// Need to patch anchor to include file name.
				a.name = location.hash.replace(/^\#/, '');
				document.location.hash = a.name;
				loaded_hash = location.hash;
			}
			hash_check = setTimeout('check_hash_navigation()', 50);
		}
		else {
			load_content();		
		}
	}
	else {
		hash_check = setTimeout('check_hash_navigation()', 50);
	}
}

function load_file(tree, file, ver, line) {
	if (!use_ajax_navigation) {
		return true;
	}

	if (hash_check) {
		clearTimeout(hash_check);
	}

	if ((pending_tree == tree) &&
	    (pending_file == file) &&
	    (pending_ver == ver))
	{
	        if (line > 0)
			line = '#L' + line;
		location.hash = location.hash.replace(/\#L\d+$/, '') + line;
		check_hash_navigation();
		return false;
	}


	var res = document.getElementById('content');

	res.innerHTML = '<div class="progress">Loading...</div>';
	pending_line = line;
	pending_tree = tree;
	pending_file = file;
	if (ver) {
		pending_ver = ver;
	}
	else {
		pending_ver = '';
	}
	
	if (!file)
		file = '/';
	if (line < 1)
		line = 1;
	pjx_load_file(['tree__' + tree, 'file__' + file, 'v__' + ver,
		       'line__' + line, 'NO_CACHE'],
		      [load_file_finalize]);
	return false;
}


function ajaxify_link_handlers(links) {
	var i;
	for (i = 0; i < links.length; i++) {
		if (links[i].className == 'fref') {
			links[i].onclick = ajax_nav;
		}
		else if (links[i].className == 'line') {
			links[i].onclick = ajax_jumpto_line;
		}
		else if (links[i].className == 'sref' || 
		    links[i].className == 'falt')
		{
			links[i].onclick = ajax_lookup_anchor; 
		}

	}
}

function load_next_pending_fragment() {
	var listing = document.getElementById('file_contents');
	if (!listing)
		return;

	for (var i = 0; i < listing.childNodes.length; i++) {
		if ((listing.childNodes[i].nodeName == 'PRE') &&
		    (listing.childNodes[i].className == 'pending'))
		{
			pjx_load_fragment(['tree__' + pending_tree,
					   'frag__' + listing.childNodes[i].id],
					  [load_fragment_finalize]);
			return;
		}
	}
}

function load_fragment_finalize(content) {
	var split = content.indexOf('|');
	var id = content.substr(0, split);
	var div = document.getElementById(id);
	if (!div)
		return;

	// Work around IE oddity where whitespace is collapsed on 
	// assignment to innerHTML unless contained in pre-tags...
	if (div.outerHTML) {
		div.outerHTML = '<pre class="done" id="' + id + '">' +
			content.substr(split+1) + '</pre>';
		div = document.getElementById(id);
	}
	else {
		div.innerHTML = content.substr(split+1);
		div.className = 'done';
	}

	var links = div.getElementsByTagName('a');
	ajaxify_link_handlers(links);
	load_next_pending_fragment();

//	if (location.hash)
//		location.hash = location.hash;
}

function load_file_finalize(content) {
	var res = document.getElementById('content');
	res.innerHTML = 'Done';
	res.innerHTML = content;
	var head = document.getElementById('current_path');
	head.innerHTML = '<a class=\"fref\" href=\".\">' + escape(pending_tree) + '</a>';
	var path_walked = '';
	var elems = pending_file.split(/\//);
	for (var i = 0; i < elems.length; i++) {
		if (elems[i] != '') {
			head.innerHTML = head.innerHTML + '/' +
				'<a class=\"fref\" href=\"' + escape(path_walked) + escape(elems[i]) +
				'\">' + escape(elems[i]) + '</a>';
			path_walked = path_walked + elems[i] + '/';
		}
	}
	document.title = 'LXR ' + pending_tree + '/' + pending_file;

	var full_tree = pending_tree;
	if (pending_ver) {
		full_tree = full_tree + '+' + pending_ver;
	}
	var full_path = full_tree + '/' + pending_file.replace(/^\/?/, '');

	var print = document.getElementById('lxr_print');
	var save  = document.getElementById('lxr_save');
	var dirlist = document.getElementById('content_dir');
	if (dirlist) {
		print.style.display = 'none';
		save.style.display = 'none';
	}
	else {
		var pform = document.getElementById('print_form');
		pform.action = '../' + full_tree + '/+print=' + 
			pending_file.replace(/^\/?/, '');
		print.style.display = 'inline';
		var sform = document.getElementById('save_form');
		sform.action = '../' + full_tree + '/+save=' + 
			pending_file.replace(/^\/?/, '');
		save.style.display = 'inline';
	}

	if (hash_check) {
		clearTimeout(hash_check);
	}

	location.hash = full_path;
	loaded_hash = location.hash;
	loaded_tree = pending_tree;
	loaded_file = pending_file;
	loaded_ver = pending_ver;

	if (pending_line) {
		location.hash = full_path + '#L' + pending_line;
	}

	hash_check = setTimeout('check_hash_navigation()', 50);

	ajaxify_link_handlers(document.links);

	load_next_pending_fragment();
}

function load_content() {
	if (!use_ajax_navigation) {
		return false;
	}
	var tree = location.hash.split('/', 1);
	tree[0].match(/^(.+?)([+](.*)|)$/);
	tree = RegExp.$1;

	var ver = '';
	if (RegExp.$2) {
		ver = RegExp.$3;
	}
	tree = tree.replace(/^#/, '');
	var file = location.hash.replace(/^[^\/]*\/?/, '');
	var line = file.split('#L');
	if (line.length > 1) {
		file = line[0];
		line = line[1];
	}
	else {
		line = '';
	}
	load_file(tree, file, ver, line);

	pjx_releases(['tree__' + tree, 'NO_CACHE'],
		     [load_content_finalize]);
}

function load_content_finalize(content) {
	var res = document.getElementById('ver_select');
	res.innerHTML = content;
	var verlist = document.getElementById('v');
	verlist.value = pending_ver;
}

function update_version(verlist, base_url, tree, defversion, path) {
	if (use_ajax_navigation) {
		var file = location.hash.replace(/^[^\/]*\//, '');
		var line;
		file.match(/\#L(\d+)/);
		line = RegExp.$1;
		file = file.replace(/\#L\d*$/, '');
	
		load_file(loaded_tree, file, verlist.value, line);
		return false;
	}
	else {
		var newurl = base_url.replace(/[^\/]*\/?$/, '');
		if (verlist.value == defversion) {
			newurl = newurl + tree;
		}
		else {
			newurl = newurl + tree + '+' + verlist.value;
		}
		newurl = newurl + '/' + path.replace(/^\//, '');
		document.location = newurl;
	}
}

function next_version() {
	var verlist = document.getElementById('v');
	if (verlist.selectedIndex > 0) {
		verlist.selectedIndex = verlist.selectedIndex - 1;
		update_version(verlist, '', '', '', '');
	}
	return false;
}

function previous_version() {
	var verlist = document.getElementById('v');
	if (verlist.selectedIndex < verlist.length - 1) {
		verlist.selectedIndex = verlist.selectedIndex + 1;
		update_version(verlist, '', '', '', '');
	}
	return false;
}

function popup_prepare(serial) {
	window_unique(serial);
	var i;
	for (i = 0; i < document.links.length; i++) {
		if (document.links[i].className == 'sref' || 
		    document.links[i].className == 'falt')
		{
			document.links[i].onclick = popup_anchor;
		}
	}
}

function ajax_lookup_anchor(event, anchor) {
	if (!use_ajax_navigation)
		return true;

	if (!anchor)
		anchor = this;
	
	lookup = anchor.href.replace(/^(https?:.*?\/.*?[+][*]\/|)/, '');

	var lvar = document.getElementById('ajax_lookup');
	lvar.value = lookup;

	var res = document.getElementById('search_results');
	res.style.display = 'block';
	res.innerHTML = '<div class="progress">Searching...</div>';

	pjx_search(['ajax_lookup', 'v', 'tree__' + loaded_tree, 'NO_CACHE'],
		   ['search_results']);
	return false;
}
