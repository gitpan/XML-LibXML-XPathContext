# $Id: XPathContext.pm,v 1.33 2005/10/20 16:56:09 pajas Exp $

package XML::LibXML::XPathContext;

use strict;
use vars qw($VERSION @ISA $USE_LIBXML_DATA_TYPES);

use XML::LibXML::NodeList;

$VERSION = '0.07';
require DynaLoader;

@ISA = qw(DynaLoader);

bootstrap XML::LibXML::XPathContext $VERSION;

# should LibXML XPath data types be used for simple objects
# when passing parameters to extension functions (default: no)
$USE_LIBXML_DATA_TYPES = 0;

sub findnodes {
    my ($self, $xpath, $node) = @_;

    my @nodes = $self->_guarded_find_call('_findnodes', $xpath, $node);

    if (wantarray) {
        return @nodes;
    }
    else {
        return XML::LibXML::NodeList->new(@nodes);
    }
}

sub find {
    my ($self, $xpath, $node) = @_;

    my ($type, @params) = $self->_guarded_find_call('_find', $xpath, $node);

    if ($type) {
        return $type->new(@params);
    }
    return undef;
}

sub findvalue {
    my $self = shift;
    return $self->find(@_)->to_literal->value;
}

sub _guarded_find_call {
    my ($self, $method, $xpath, $node) = @_;

    my $prev_node;
    if (ref($node)) {
        $prev_node = $self->getContextNode();
        $self->setContextNode($node);
    }
    my @ret;
    eval {
        @ret = $self->$method($xpath);
    };
    $self->_free_node_pool;
    $self->setContextNode($prev_node) if ref($node);

    if ($@) { die "ERROR: $@"; }

    return @ret;
}

sub registerFunction {
    my ($self, $name, $sub) = @_;
    $self->registerFunctionNS($name, undef, $sub);
    return;
}

sub unregisterNs {
    my ($self, $prefix) = @_;
    $self->registerNs($prefix, undef);
    return;
}

sub unregisterFunction {
    my ($self, $name) = @_;
    $self->registerFunctionNS($name, undef, undef);
    return;
}

sub unregisterFunctionNS {
    my ($self, $name, $ns) = @_;
    $self->registerFunctionNS($name, $ns, undef);
    return;
}

sub unregisterVarLookupFunc {
    my ($self) = @_;
    $self->registerVarLookupFunc(undef, undef);
    return;
}

# extension function perl dispatcher
# borrowed from XML::LibXSLT

sub _perl_dispatcher {
    my $func = shift;
    my @params = @_;
    my @perlParams;

    my $i = 0;
    while (@params) {
        my $type = shift(@params);
        if ($type eq 'XML::LibXML::Literal' or
            $type eq 'XML::LibXML::Number' or
            $type eq 'XML::LibXML::Boolean')
        {
            my $val = shift(@params);
            unshift(@perlParams, $USE_LIBXML_DATA_TYPES ? $type->new($val) : $val);
        }
        elsif ($type eq 'XML::LibXML::NodeList') {
            my $node_count = shift(@params);
            unshift(@perlParams, $type->new(splice(@params, 0, $node_count)));
        }
    }

    $func = "main::$func" unless ref($func) || $func =~ /(.+)::/;
    no strict 'refs';
    my $res = $func->(@perlParams);
    return $res;
}


1;

__END__

=head1 NAME

XML::LibXML::XPathContext - Perl interface to libxml2's xmlXPathContext

=head1 SYNOPSIS

    use XML::LibXML::XPathContext;

    my $xc = XML::LibXML::XPathContext->new;
    my $xc = XML::LibXML::XPathContext->new($node);

    my $node = $xc->getContextNode;
    $xc->setContextNode($node);

    my $position = $xc->getContextPosition;
    $xc->setContextPosition($position);
    my $size = $xc->getContextSize;
    $xc->setContextSize($size);

    $xc->registerNs($prefix, $namespace_uri);
    $xc->unregisterNs($prefix);
    my $namespace_uri = $xc->lookupNs($prefix);

    $xc->registerFunction($name, sub { ... });
    $xc->registerFunctionNS($name, $namespace_uri, sub { ... });
    $xc->unregisterFunction($name);
    $xc->unregisterFunctionNS($name, $namespace_uri);

    $xc->registerVarLookupFunc(sub { ... }, $data);
    $xc->unregisterVarLookupFunc($name);
    $data = $xc->getVarLookupData();
    $sub = $xc->getVarLookupFunc();

    my @nodes = $xc->findnodes($xpath);
    my @nodes = $xc->findnodes($xpath, $context_node);
    my $nodelist = $xc->findnodes($xpath);
    my $nodelist = $xc->findnodes($xpath, $context_node);
    my $result = $xc->find($xpath);
    my $result = $xc->find($xpath, $context_node);
    my $value = $xc->findvalue($xpath);
    my $value = $xc->findvalue($xpath, $context_node);


=head1 DESCRIPTION

This module augments L<XML::LibXML|XML::LibXML> by providing Perl
interface to libxml2's xmlXPathContext structure.  Besides just
performing xpath statements on L<XML::LibXML|XML::LibXML>'s node trees
it allows redefining certaint aspects of XPath engine.  This modules
allows

=over 4

=item 1

registering namespace prefixes,

=item 2

defining XPath functions in Perl,

=item 3

defining variable lookup functions in Perl.

=item 3

cheating the context about current proximity position and context size

=back

=head1 EXAMPLES

=head2 Find all paragraph nodes in XHTML document

This example demonstrates I<registerNs()> usage:

    my $xc = XML::LibXML::XPathContext->new($xhtml_doc);
    $xc->registerNs('xhtml', 'http://www.w3.org/1999/xhtml');
    my @nodes = $xc->findnodes('//xhtml:p');

=head2 Find all nodes whose names match a Perl regular expression

This example demonstrates I<registerFunction()> usage:

    my $perlmatch = sub {
        die "Not a nodelist"
            unless $_[0]->isa('XML::LibXML::NodeList');
        die "Missing a regular expression"
            unless defined $_[1];

        my $nodelist = XML::LibXML::NodeList->new;
        my $i = 0;
        while(my $node = $_[0]->get_node($i)) {
            $nodelist->push($node) if $node->nodeName =~ $_[1];
            $i ++;
        }

        return $nodelist;
    };

    my $xc = XML::LibXML::XPathContext->new($node);
    $xc->registerFunction('perlmatch', $perlmatch);
    my @nodes = $xc->findnodes('perlmatch(//*, "foo|bar")');

=head2 Use XPath variables to recycle results of previous evaluations

This example demonstrates I<registerVarLookup()> usage:

    sub var_lookup {
      my ($varname,$ns,$data)=@_;
      return $data->{$varname};
    }

    my $areas = XML::LibXML->new->parse_file('areas.xml');
    my $empl = XML::LibXML->new->parse_file('employees.xml');

    my $xc = XML::LibXML::XPathContext->new($empl);

    my %results =
      (
       A => $xc->find('/employees/employee[@salary>10000]'),
       B => $areas->find('/areas/area[district='Brooklyn']/street'),
      );

    # get names of employees from $A woring in an area listed in $B
    $xc->registerVarLookupFunc(\&var_lookup, \%results);
    my @nodes = $xc->findnodes('$A[work_area/street = $B]/name');

=head1 METHODS

=over 4

=item B<new>

Creates a new XML::LibXML::XPathContext object without a context node.

=item B<new($node)>

Creates a new XML::LibXML::XPathContext object with the context node
set to I<$node>.

=item B<registerNs($prefix, $namespace_uri)>

Registers namespace I<$prefix> to I<$namespace_uri>.

=item B<unregisterNs($prefix)>

Unregisters namespace I<$prefix>.

=item B<lookupNs($prefix)>

Returns namespace URI registered with I<$prefix>. If I<$prefix> is not
registered to any namespace URI returns C<undef>.

=item B<registerVarLookupFunc($callback, $data)>

Registers variable lookup function I<$prefix>. The registered function
is executed by the XPath engine each time an XPath variable is
evaluated. It takes three arguments: I<$data>, variable name, and
variable ns-URI and must return one value: a number or string or any
L<XML::LibXML|XML::LibXML> object that can be a result of findnodes:
Boolean, Literal, Number, Node (e.g. Document, Element, etc.), or
NodeList.  For convenience, simple (non-blessed) array references
containing only L<XML::LibXML::Node|XML::LibXML::Node> objects can be
used instead of a L<XML::LibXML::NodeList|XML::LibXML::NodeList>.

=item B<getVarLookupData()>

Returns the data that have been associated with a variable lookup
function during a previous call to I<registerVarLookupFunc>.

=item B<unregisterVarLookupFunc()>

Unregisters variable lookup function and the associated lookup data.

=item B<registerFunctionNS($name, $uri, $callback)>

Registers an extension function I<$name> in I<$uri>
namespace. I<$callback> must be a CODE reference. The arguments of the
callback function are either simple scalars or
L<XML::LibXML::NodeList|XML::LibXML::NodeList> objects depending on
the XPath argument types. The function is responsible for checking the
argument number and types. Result of the callback code must be a
single value of the following types: a simple scalar (number,string)
or an arbitrary L<XML::LibXML|XML::LibXML> object that can be a result
of findnodes: Boolean, Literal, Number, Node (e.g. Document, Element,
etc.), or NodeList. For convenience, simple (non-blessed) array
references containing only L<XML::LibXML::Node|XML::LibXML::Node>
objects can be used instead of a
L<XML::LibXML::NodeList|XML::LibXML::NodeList>.

=item B<unregisterFunctionNS($name, $uri)>

Unregisters extension function I<$name> in I<$uri> namespace. Has the
same effect as passing C<undef> as I<$callback> to registerFunctionNS.

=item B<registerFunction($name, $callback)>

Same as I<registerFunctionNS> but without a namespace.

=item B<unregisterFunction($name)>

Same as I<unregisterFunctionNS> but without a namespace.

=item B<findnodes($xpath, [ $context_node ])>

Performs the xpath statement on the current node and returns the
result as an array. In scalar context returns a
L<XML::LibXML::NodeList|XML::LibXML::NodeList> object. Optionally, a
node may be passed as a second argument to set the context node for
the query.

=item B<find($xpath, [ $context_node ])>

Performs the xpath expression using the current node as the context of
the expression, and returns the result depending on what type of
result the XPath expression had. For example, the XPath C<1 * 3 + 52>
results in a L<XML::LibXML::Number|XML::LibXML::Number> object being
returned. Other expressions might return a
L<XML::LibXML::Boolean|XML::LibXML::Boolean> object, or a
L<XML::LibXML::Literal|XML::LibXML::Literal> object (a string). Each
of those objects uses Perl's overload feature to "do the right thing"
in different contexts. Optionally, a node may be passed as a second
argument to set the context node for the query.


=item B<findvalue($xpath, [ $context_node ])>

Is exactly equivalent to:

    $node->find( $xpath )->to_literal;

That is, it returns the literal value of the results.  This enables
you to ensure that you get a string back from your search, allowing
certain shortcuts. This could be used as the equivalent of
<xsl:value-of select="some_xpath"/>. Optionally, a node may be passed
in the second argument to set the context node for the query.

=item B<getContextNode()>

Get the current context node.

=item B<setContextNode($node)>

Set the current context node.

=item B<setContextPosition($position)>

Set the current proximity position. By default, this value is -1 (and
evaluating XPath function position() in the initial context raises an
XPath error), but can be set to any value up to context size. This
usually only serves to cheat the XPath engine to return given position
when position() XPath function is called. Setting this value to -1
restores the default behavior.

=item B<getContextPosition()>

Get the current proximity position.

=item B<setContextSize($size)>

Set the current size. By default, this value is -1 (and evaluating
XPath function last() in the initial context raises an XPath error),
but can be set to any non-negative value. This usually only serves to
cheat the XPath engine to return the given value when last() XPath
function is called. If context size is set to 0, position is
automatically also set to 0. If context size is positive, position is
automatically set to 1. Setting context size to -1 restores the
default behavior.

=item B<getContextPosition()>

Get the current proximity position.

=item B<setContextNode($node)>

Set the current context node.

=back

=head1 BUGS AND CAVEATS

From version 0.06, XML::LibXML::XPathContext objects B<are> reentrant,
meaning that you can call methods of an XML::LibXML::XPathContext even
from XPath extension functions registered with the same object or from
a variable lookup function.  On the other hand, you should rather
avoid registering new extension functions, namespaces and a variable
lookup function from within extension functions and a variable lookup
function, unless you want to experience untested behavior.

=head1 AUTHORS

Based on L<XML::LibXML|XML::LibXML> and L<XML::XSLT|XML::XSLT> code by
Matt Sergeant and Christian Glahn.

Maintained by Ilya Martynov and Petr Pajas.

Copyright 2001-2003 AxKit.com Ltd, All rights reserved.

=head1 SUPPORT

For suggestions, bugreports etc. you may contact the maintainers
directly (ilya@martynov.org and pajas@ufal.ms.mff.cuni.cz)

XML::LibXML::XPathContext issues can be discussed among other things
on the perl XML mailing list (perl-xml@listserv.ActiveState.com).

=head1 SEE ALSO

L<XML::LibXML|XML::LibXML>, L<XML::XSLT|XML::XSLT>

=cut
