package Posy::Plugin::InfoFind;
use strict;

=head1 NAME

Posy::Plugin::InfoFind - Posy plugin to find files using their Info content.

=head1 VERSION

This describes version B<0.0502> of Posy::Plugin::InfoFind.

=cut

our $VERSION = '0.0502';

=head1 SYNOPSIS

    @plugins = qw(Posy::Core
		  ...
		  Posy::Plugin::Info
		  Posy::Plugin::InfoFind
		  ...);
    @actions = qw(init_params
	    ...
	    head_template
	    infofind_set
	    head_render
	    ...
	);

=head1 DESCRIPTION

This plugin checks the parameters for a find query, and uses the .info
files defined by the Posy::Plugin::Info plugin to search for files
depending on their Info information.  Thus this depends on the
Posy::Plugin::Info plugin.

This plugin sets the page-type to 'info_find', so that one can make
find-specific flavour templates.  Then it falls back on the 'find'
and 'category' page-types.

Note that all fields you wish to be able to search on must be defined
in the info_type_spec config variable.

The search form will search from the current directory downwards.
This enables you to customize the particular Info setup to be different
in different directories.  If you want to search the whole site,
the search form needs to be put in a file at the top of the site.

This fills in a few variables which can be used within your
flavour templates.
You can also use them in your entry files if you are using
the Posy::Plugin::TextTemplate plugin.

=over

=item $flow_infofind_form

Contains a search-form definition for setting the 'info_find' parameters.

=item $flow_infofind_criteria

Contains the values which were searched on; useful for putting on a
results page.

=item $flow_infofind_sort_criteria

Contains the fields which were sorted by; useful for putting on a
results page.

=item $flow_num_found

The number of entries which were found which matched the search parameters.

=back

This plugin also provides some L</Helper Methods> which can be called
from within flavour templates and/or entries if one is using the
Posy::Plugin::TextTemplate plugin.

=head2 Cautions

This plugin does not work if you have a hybrid site (partially
static-generated, partially dynamic) and also use the
Posy::Plugin:;Canonical plugin, since the Canonical plugin will redirect
your search query.  Also, if you have a hybrid site, don't forget to set
the L</infofind_url> config variable.

Search result pages cannot be generated with static-generation.

=head2 Activation

This plugin needs to be added to the plugins list and the actions list.
This overrides the 'select_entries' 'parse_path' 'get_alt_path_types'
methods; therefore care needs to be taken with other plugins if they
override the same methods.

In the actions list 'infofind_set' needs to go somewhere after
B<head_template> and before B<head_render>, since this needs
to set values before the head is rendered.

=head2 Configuration

This expects configuration settings in the $self->{config} hash,
which, in the default Posy setup, can be defined in the main "config"
file in the config directory.

=over

=item B<infofind_field_size>

The size to make the length of the input fields for the form.
(default: 50)

=item B<infofind_url>

The URL to use for the "action" part of the search form.
This defaults to the global $self->{url} value, but may
need to be overridden for things like a hybrid static/dynamic site.
This is because the global $self->{url} for static generation
needs to hide the name of the script used to generate it,
but this plugin needs to know the path to the CGI script.
If this is set, this plugin assumes this is a hybrid site
and makes its links with explicit 'path' parameters.

=back

=cut

=head1 OBJECT METHODS

Documentation for developers and those wishing to write plugins.

=head2 init

Do some initialization; make sure that default config values are set.

=cut
sub init {
    my $self = shift;
    $self->SUPER::init();

    # set defaults
    $self->{config}->{infofind_field_size} = 50
	if (!defined $self->{config}->{infofind_field_size});
    $self->{config}->{infofind_url} = ''
	if (!defined $self->{config}->{infofind_url});
    $self->{config}->{infofind_field_prefix} = 'infofind_field_'
	if (!defined $self->{config}->{infofind_field_prefix});
} # init

=head1 Flow Action Methods

Methods implementing actions.

=head2 parse_path

Parse the PATH_INFO (or 'path' parameter) to get the parts of the path
and figure out various bits of information about the path.

Calls the parent 'parse_path' then checks if the 'find' parameter
is set (and there is no error), and sets the path-type to find, if so.

=cut
sub parse_path {
    my $self = shift;
    my $flow_state = shift;

    $self->SUPER::parse_path($flow_state);

    if (!$self->{path}->{error} 
	&& $self->param('info_find'))
    {
	$self->{path}->{type} = 'info_find';
    }

    1;
} # parse_path

=head2 select_entries

$self->select_entries($flow_state);

If the path-type is 'find', checks and uses the 'find' parameter value as a
regular expression to grep for files.  Uses the category directory given
in the path as the directory to start from.
Sets $flow_state->{find} if the find parameter is legal.
Sets $flow_state->{num_found} to the number of matching entries.

Otherwise, just selects entries by looking at the path information.

Assumes that no entries have been selected before.  Sets
$flow_state->{entries}.  Assumes it hasn't already been set.

=cut
sub select_entries {
    my $self = shift;
    my $flow_state = shift;

    if ($self->{path}->{type} eq 'info_find')
    {
	my $find_param = $self->param('info_find');
	$find_param =~ /([^`'"]+)/; # untaint
	my $find_task = $1;

	if ($find_task)
	{
	    my $field_prefix = $self->{config}->{infofind_field_prefix};
	    # set up the search params
	    my $find_criteria = '';
	    my %find_check = ();
	    while (my $fld = each %{$self->{config}->{info_type_spec}})
	    {
		my $fparam = $field_prefix . $fld;
		if ($self->param($fparam))
		{
		    my $pval = $self->param($fparam);
		    $pval =~ /([^`]+)/; # untaint
		    $find_check{$fld} = $1;
		    $find_criteria .= " $fld=$1";
		    # replace unhelpful characters
		    $find_check{$fld} =~ s/'/./g;
		    $find_check{$fld} =~ s/"/./g;
		    $find_check{$fld} =~ s#/#.#g;
		}
	    }
	    $flow_state->{infofind_criteria} = $find_criteria;
	    if ($self->{config}->{info_sort_param}
		and $self->param($self->{config}->{info_sort_param}))
	    {
		my (@sort_params) = $self->param($self->{config}->{info_sort_param});
		# only use non-empty values
		my $sort_criteria = '';
		foreach my $sp (@sort_params)
		{
		    if ($sp)
		    {
			if ($sort_criteria)
			{
			    $sort_criteria .= ", $sp"
			}
			else
			{
			    $sort_criteria = $sp;
			}
		    }
		}
		$flow_state->{infofind_sort_criteria} = $sort_criteria;
	    }

	    $flow_state->{entries} = [];
	    $self->{path}->{cat_id} =~ m#([-_.\/\w]+)#;
	    my $cat_id = $1; # untaint
	    $cat_id = '' if (!$self->{path}->{cat_id});
	    # figure out which entries have .info files we're interested in
	    my @search_ids = ();
	    while (my $ffile = each(%{$self->{others}}))
	    {
		if (($ffile =~ /\.info$/)
		    and ($cat_id eq ''
			 or $self->{others}->{$ffile} eq $cat_id
			 or $self->{others}->{$ffile} =~ m#^$cat_id/#))
		{
		    my ($ff_nobase, $suffix) = $ffile =~ /^(.*)\.(\w+)$/;
		    my $fpath = File::Spec->abs2rel($ff_nobase,
						    $self->{data_dir});
		    my @path_split = File::Spec->splitdir($fpath);
		    my $file_id = join('/', @path_split);
		    if (exists $self->{files}->{$file_id})
		    {
			push @search_ids, $file_id;
		    }
		}
	    }
	    # now check the info of the entries
	    my %found_ids = ();
	    foreach my $fid (@search_ids)
	    {
		$self->debug(2, "InfoFind looking at $fid");
		my %info = $self->info($fid);
		# check each of the params
		my $matched = 0;
		foreach my $field (keys %find_check)
		{
		    my $check = $find_check{$field};
		    if ($info{$field} =~ m/$check/s)
		    {
			$self->debug(3, "InfoFind $field=$info{$field} found=$check");
			$matched = 1;
		    }
		    else
		    {
			$self->debug(3, "InfoFind $field=$info{$field} NOTfound=$check");
			$matched = 0;
			last;
		    }
		}
		if ($matched)
		{
		    $found_ids{$fid} = 1;
		}
	    }

	    # now put all the found entries into the entry array
	    while (my $fid = each(%found_ids))
	    {
		push @{$flow_state->{entries}}, $fid;
	    }
	    $self->debug(2, join(":", @{$flow_state->{entries}}));
	    
	    my $num_found = @{$flow_state->{entries}};
	    $flow_state->{num_found} = $num_found;
	}
	else
	{
	    $self->SUPER::select_entries($flow_state);
	}
    }
    else
    {
	$self->SUPER::select_entries($flow_state);
    }
} # select_entries

=head2 infofind_set

$self->infofind_set($flow_state)

Sets $flow_state->{infofind_form} 
(aka $flow_infofind_form)
to be used inside flavour files.

=cut
sub infofind_set {
    my $self = shift;
    my $flow_state = shift;

    if (defined $self->{config}->{info_type_spec})
    {
	$flow_state->{infofind_form} = $self->infofind_make_form();
    }
    1;
} # infofind_set

=head1 Helper Methods

Methods which can be called from within other methods, or from within
a flavour or entry file if using a plugin such as Posy::Plugin::TextTemplate.

=head2 infofind_make_form

<?perl $Posy->infofind_make_form(fields=>\@fields); perl?>

Makes the InfoFind search form with the given fields;
uses the fields defined in the info_type_spec config
variable if no fields are given.

This is useful if you wish to change which fields to search
on, or change their order in the search form.

=cut
sub infofind_make_form {
    my $self = shift;
    my %args = (
	@_
    );

    if ($self->{config}->{info_type_spec})
    {
	my $submit_name = 'info_find';
	my $field_prefix = $self->{config}->{infofind_field_prefix};
	my $path = $self->{path}->{info};
	my $action;
	if ($self->{config}->{infofind_url})
	{
	    $action = $self->{config}->{infofind_url};
	}
	else
	{
	    $action = $self->{url} . $path;
	}
	my @fields = ($args{fields}
		      ? @{$args{fields}}
		      : sort keys %{$self->{config}->{info_type_spec}});

	my $form=<<EOT;
<form action="$action">
EOT
	# add path as a hidden parameter if need be
	if ($self->{config}->{infofind_url})
	{
	    $form .="<input type=\"hidden\" name=\"path\" value=\"$path\"/>";
	}
	my $info_sort_label = $self->{config}->{info_sort_param};
	my $info_sort_reverse_label = $self->{config}->{info_sort_param_reverse};
	$form .=<<EOT;
<table border="0">
<tr><th>Match Fields</th>
EOT
	if ($info_sort_label)
	{
	    $form .= "<th>Sort</th>";
	    $form .= "<th>Reversed</th>";
	}
	$form .=<<EOT;
</tr><tr>
<td><table border="1">
EOT
	foreach my $field (@fields)
	{
	    $form .= "<tr><td><strong>$field</strong></td>\n";
	    my $field_label = $field_prefix . $field;
	    my $use_default_type =
		    (!exists $self->{config}->{info_type_spec}->{$field});
	    my $field_type =
		($use_default_type
		 ? 'string'
		 : $self->{config}->{info_type_spec}->{$field}->{type});
	    if ($field_type eq 'string'
		|| $field_type eq 'title'
		|| $field_type eq 'number'
		|| $field_type eq 'text')
	    {
		my $size = $self->{infofind_field_size};
		$form .=<<EOT;
<td><input type="text" name="$field_label" size="$size"/>
EOT
	    }
	    elsif ($field_type eq 'limited')
	    {
		my @values =
		    @{$self->{config}->{info_type_spec}->{$field}->{'values'}};
		$form .=<<EOT;
<td><select name="$field_label">
EOT
		$form .= "<option value=''>-- select --</option>\n";
		foreach my $opt (@values)
		{
		    $form .= "<option>$opt</option>\n";
		}
		$form .="</select>";
	    }
	    $form .= "</td></tr>\n";
	}
	$form .= "</table></td>";
	if ($info_sort_label)
	{
	    $form .= "<td><table border='1'>";
	    # and the sorting
	    foreach my $field (@fields)
	    {
		$form .="<tr>";
		$form .=<<EOT;
<td><select name="$info_sort_label">
EOT
		$form .= "<option value=''>-- sort by --</option>\n";
		foreach my $fld (@fields)
		{
		    $form .= "<option>$fld</option>\n";
		}
		$form .="</select></td>";
		$form .="</tr>\n";
	    }
	    $form .="</table></td>";
	    # reversed
	    $form .= "<td><table border='1'>";
	    foreach my $field (@fields)
	    {
		$form .="<tr>";
		$form .=<<EOT;
<td><input type="checkbox" name="$info_sort_reverse_label" value="$field">$field</input><td></tr>
EOT
	    }
	    $form .="</table></td>";
	}
	$form.=<<EOT1;
</tr></table>
<input type="Submit" name="$submit_name" value="Search"/>
<input type="Reset"/>
EOT1
	$form.="</form>";
	return $form;
    }
    return '';
} # infofind_make_form

=head2 infofind_header_field

    [==
    $header_field = $Posy->infofind_header_field(0);
    ==]

Gives the name of the Info field which would be the header
at this level of headers.  (Allows for multiple levels of
header because of the possibility of using Posy::Plugin::MultiHeader)

Useful for making generic search-result templates.

=cut
sub infofind_header_field {
    my $self = shift;
    my $level = (@_ ? shift : 0);

    if (($self->{config}->{info_sort_param}
	 and $self->param($self->{config}->{info_sort_param}))
	or $self->{config}->{info_sort_spec})
    {
	my (@sort_fields) = (
	    ($self->{config}->{info_sort_param}
		and $self->param($self->{config}->{info_sort_param}))
	    ?  $self->param($self->{config}->{info_sort_param})
	    : @{$self->{config}->{info_sort_spec}->{order}});
	if ($level < @sort_fields)
	{
	    if ($sort_fields[$level])
	    {
		return $sort_fields[$level];
	    }
	    else
	    {
		return undef;
	    }
	}
    }
    return undef;
} # infofind_header_field

=head2 infofind_is_in_header

    [==
    if ($Posy->infofind_is_in_header($field, $level)) {
    ...
    }
    ==]

Returns true if the field is in a header lower than
or equal to the given level.
Useful for making generic search-result templates.

=cut
sub infofind_is_in_header {
    my $self = shift;
    my $field = shift;
    my $level = (@_ ? shift : 0);

    if ($field
	and (($self->{config}->{info_sort_param}
	      and $self->param($self->{config}->{info_sort_param}))
	     or $self->{config}->{info_sort_spec})
       )
    {
	my (@sort_fields) = (
	    ($self->{config}->{info_sort_param}
		and $self->param($self->{config}->{info_sort_param}))
	    ?  $self->param($self->{config}->{info_sort_param})
	    : @{$self->{config}->{info_sort_spec}->{order}});
	for (my $i = 0; ($i <= $level && $i < @sort_fields); $i++)
	{
	    if ($field eq $sort_fields[$i])
	    {
		return 1;
	    }
	}
    }
    return 0;
} # infofind_is_in_header

=head2 infofind_make_index

    <?perl
    $Posy->infofind_make_index(field=>'Author',
	category=>'fiction/stories',
	rel_link=>'fiction/stories/series.html',
	indexstyle=>'medium',
	pre_alpha=>'<h2>',
	post_alpha=>'</h2>',
	pre_list=>'<ul>'.
	post_list=>'</ul>',
	pre_item=>'<li>',
	post_item=>'</li>',
	item_sep=>'');
    perl?>

Makes an quick-search index of the given field.  

indexstyle can be 'long', 'medium' or 'short'.

The medium style is the default, and makes a list of links
made up of all the unique values of that field; each link
is a link to a search to match that value exactly.

The long style is similar to the medium style, but the list is
split into multiple lists, grouped by the first letter.

The short style is a list of just the first letter values of
that field, with a link to search for entries with that field
starting with that letter.

=cut
sub infofind_make_index {
    my $self = shift;
    my %args = (
	indexstyle=>'medium',
	category=>'',
	rel_link=>'',
	field=>'',
	@_
    );
    my $field = $args{field};
    my $cat_id = $args{category};

    # figure out which entries have .info files we're interested in
    my @search_ids = ();
    while (my $ffile = each(%{$self->{others}}))
    {
	if (($ffile =~ /\.info$/)
	    and ($cat_id eq ''
		 or $self->{others}->{$ffile} eq $cat_id
		 or $self->{others}->{$ffile} =~ m#^$cat_id/#))
	{
	    my ($ff_nobase, $suffix) = $ffile =~ /^(.*)\.(\w+)$/;
	    my $fpath = File::Spec->abs2rel($ff_nobase,
					    $self->{data_dir});
	    my @path_split = File::Spec->splitdir($fpath);
	    my $file_id = join('/', @path_split);
	    if (exists $self->{files}->{$file_id})
	    {
		push @search_ids, $file_id;
	    }
	}
    }
    # get all the unique values for this field
    # but don't add the empty value
    my $sort_type = ($self->{config}->{info_type_spec}->{$field}->{type}
		     ?  $self->{config}->{info_type_spec}->{$field}->{type}
		     : 'string');
    my %values = ();
    foreach my $fid (@search_ids)
    {
	my $val = $self->info($fid, field=>$field);
	$values{$val} = $val if $val;
	# set the "sorting" value
	if ($val and $sort_type eq 'title')
	{
	    # strip the A and The from titles
	    $values{$val} =~ s/^(The\s+|A\s+)//;
	}
    }
    # sort the values taking into account the info type
    my @indvals = sort {
	if ($sort_type eq 'number')
	{
	    return ($a <=> $b);
	}
	elsif ($sort_type eq 'title')
	{
	    return $values{$a} cmp $values{$b};
	}
	else
	{
	    return (uc($a) cmp uc($b));
	}
    } keys %values;

    my $indlist = '';
    if ($args{indexstyle} eq 'long')
    {
	my @lol = $self->_infofind_alphasplit(field=>$field,
	    field_values=>\@indvals);
	$indlist = $self->_infofind_long_links(\@lol, %args);
    }
    elsif ($args{indexstyle} eq 'short')
    {
	my @letters = $self->_infofind_alphasplit(field=>$field,
	    field_values=>\@indvals,
	    alpha_only=>1);
	$indlist = $self->_infofind_make_links(\@letters, %args);
    }
    else # medium
    {
	$indlist = $self->_infofind_make_links(\@indvals, %args);
    }
    return $indlist;
} # infofind_make_index

=head2 get_alt_path_types

my @alt_path_types = $self->get_alt_path_types($path_type)

Return an array of possible alternative path-types (to use
for matching in things like get_template and get_config).
The array may be empty.

If the path-type is 'info_find' returns alternatives; otherwise
calls the parent method.

=cut
sub get_alt_path_types {
    my $self = shift;
    my $path_type = shift;

    if ($path_type eq 'info_find')
    {
	my @alt_pts = qw(find category);

	return @alt_pts;
    }
    else
    {
	return $self->SUPER::get_alt_path_types($path_type);
    }
} # get_alt_path_types

=head1 Private Methods

=head2 _infofind_alphasplit

$list = $self->_infofind_alphasplit(field_values=>\@vals,
	alpha_only=>0);

Take a list of values, and split by alpha.
If alpha_only is true, return a list of just the
the first alpha letter of all the values.
If false (the default) return a list of lists, containing
both the first-letters and the values grouped by first-letter.

=cut
sub _infofind_alphasplit {
    my $self = shift;
    my %args = (
	field=>undef,
	field_values=>undef,
	alpha_only=>0,
	@_
    );
    my @vals = @{$args{field_values}};

    my @list_of_lists = ();
    my $prev_alpha = '';
    my $sublist = [];
    my $sort_type = ($self->{config}->{info_type_spec}->{$args{field}}->{type}
		     ?  $self->{config}->{info_type_spec}->{$args{field}}->{type}
		     : 'string');
    foreach my $val (@vals)
    {
	my $alpha = uc(substr($val,0,1));
	# for titles, drop the leading A or The
	if ($sort_type eq 'title'
	    and $val =~ m/^(The\s+|A\s+)(.)/)
	{
	    $alpha = uc($2);
	}
	if ($alpha ne $prev_alpha)
	{
	    push @list_of_lists, $sublist
		if (@{$sublist} and !$args{apha_only});
	    push @list_of_lists, $alpha;
	    $prev_alpha = $alpha;
	    $sublist = [];
	}
	push @{$sublist}, $val if (!$args{alpha_only});
    }
    push @list_of_lists, $sublist
	if (@{$sublist} and !$args{apha_only});
    return @list_of_lists;
} # _infofind_alphasplit

=head2 _infofind_long_links

Traverse the given list of lists values to make a set of
lists of links.

=cut
sub _infofind_long_links {
    my $self = shift;
    my $lol_ref = shift;
    my %args = (
	field=>undef,
	category=>'',
	rel_link=>'',
	pre_alpha=>'<h2>',
	post_alpha=>'</h2>',
	@_
    );
    my @list_of_lists = @{$lol_ref};

    my @items = ();
    foreach my $ll (@list_of_lists)
    {
	# if it's not a ref, it's an alpha
	if (!ref $ll)
	{
	    my $item;
	    my $label = $ll;
	    $item = join('',
			 $args{pre_alpha},
			 $label,
			 $args{post_alpha}
			);
	    push @items, $item;
	}
	else # a list
	{
	    push @items, $self->_infofind_make_links($ll, %args);
	}
    }
    my $list = join("\n", @items);
    return $list;
} # _infofind_long_links

=head2 _infofind_make_links

Traverse the given list of values to make a list of links.

=cut
sub _infofind_make_links {
    my $self = shift;
    my $list_ref = shift;
    my %args = (
	field=>undef,
	indexstyle=>'medium',
	category=>'',
	rel_link=>'',
	pre_list=>'<ul>',
	post_list=>'</ul>',
	pre_item=>'<li>',
	post_item=>'</li>',
	item_sep=>"\n",
	@_
    );

    # make a default sort order
    my @sort_order = ($args{field});
    if ($self->{config}->{info_sort_spec}->{order})
    {
	foreach my $fld (@{$self->{config}->{info_sort_spec}->{order}})
	{
	    # skip the index field sonce it's first
	    if ($fld ne $args{field})
	    {
		push @sort_order, $fld;
	    }
	}
    }
    my @sort_q = ();
    foreach my $fld (@sort_order)
    {
	push @sort_q, join('',
	    $self->{config}->{info_sort_param}, '=', $fld);
    }
    my $sort_q = join(';', @sort_q);
    my $rel_link = ($args{rel_link} ? $args{rel_link} : $args{category});
    my $sort_type = ($self->{config}->{info_type_spec}->{$args{field}}->{type}
		     ?  $self->{config}->{info_type_spec}->{$args{field}}->{type}
		     : 'string');
    my @items = ();
    foreach my $val (@{$list_ref})
    {
	my $item;
	my $label = $val;
	my $match_q = $val;
	# escape special characters
	$match_q =~ s#\(#\\\(#g;
	$match_q =~ s#\)#\\\)#g;
	$match_q =~ s#\[#\\\[#g;
	$match_q =~ s#\]#\\\]#g;
	$match_q =~ s#'#.#g;
	$match_q =~ s#"#.#g;
	if ($sort_type eq 'title')
	{
	    $match_q = '(A |The )*' . $match_q;
	}
	$match_q = $self->{cgi}->url_encode($match_q);
	my $link;
	$link = join('', 
		     '<a href="', $self->{url}, '/', $rel_link,
		     '?info_find=1;', 
		     $self->{config}->{infofind_field_prefix},
		     $args{field}, '=^', $match_q,
		     ($args{indexstyle} eq 'short' ? '' : '$'),
		     ';', $sort_q,
		     '">',
		     $label,
		     '</a>');
	$item = join('', $args{pre_item}, $link,
		     $args{post_item});
	push @items, $item;
    }
    my $list = join($args{item_sep}, @items);
    return join('', $args{pre_list}, $list, $args{post_list});

} # _infofind_make_links

=head1 INSTALLATION

Installation needs will vary depending on the particular setup a person
has.

=head2 Administrator, Automatic

If you are the administrator of the system, then the dead simple method of
installing the modules is to use the CPAN or CPANPLUS system.

    cpanp -i Posy::Plugin::InfoFind

This will install this plugin in the usual places where modules get
installed when one is using CPAN(PLUS).

=head2 Administrator, By Hand

If you are the administrator of the system, but don't wish to use the
CPAN(PLUS) method, then this is for you.  Take the *.tar.gz file
and untar it in a suitable directory.

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you're on a platform (like DOS or Windows) that doesn't like the
"./" notation, you can do this:

   perl Build.PL
   perl Build
   perl Build test
   perl Build install

=head2 User With Shell Access

If you are a user on a system, and don't have root/administrator access,
you need to install Posy somewhere other than the default place (since you
don't have access to it).  However, if you have shell access to the system,
then you can install it in your home directory.

Say your home directory is "/home/fred", and you want to install the
modules into a subdirectory called "perl".

Download the *.tar.gz file and untar it in a suitable directory.

    perl Build.PL --install_base /home/fred/perl
    ./Build
    ./Build test
    ./Build install

This will install the files underneath /home/fred/perl.

You will then need to make sure that you alter the PERL5LIB variable to
find the modules, and the PATH variable to find the scripts (posy_one,
posy_static).

Therefore you will need to change:
your path, to include /home/fred/perl/script (where the script will be)

	PATH=/home/fred/perl/script:${PATH}

the PERL5LIB variable to add /home/fred/perl/lib

	PERL5LIB=/home/fred/perl/lib:${PERL5LIB}

=head1 REQUIRES

    Test::More
    grep

=head1 SEE ALSO

perl(1).
Posy

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    perlkat AT katspace dot com
    http://www.katspace.com

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2005 by Kathryn Andersen

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Posy::Plugin::InfoFind
__END__
