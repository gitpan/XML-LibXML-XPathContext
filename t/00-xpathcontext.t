use Test;
BEGIN { plan tests => 17 };

use XML::LibXML;
use XML::LibXML::XPathContext;

my $doc = XML::LibXML->new->parse_string(<<'XML');
<foo><bar a="b"></bar></foo>
XML

# test findnodes() in list context
my @nodes = XML::LibXML::XPathContext->new($doc)->findnodes('/*');
ok(@nodes == 1);
ok($nodes[0]->nodeName eq 'foo');
ok((XML::LibXML::XPathContext->new($nodes[0])->findnodes('bar'))[0]->nodeName
   eq 'bar');

# test findnodes() in scalar context
my $nl = XML::LibXML::XPathContext->new($doc)->findnodes('/*');
ok($nl->pop->nodeName eq 'foo');
ok(!defined($nl->pop));

# test findvalue()
ok(XML::LibXML::XPathContext->new($doc)->findvalue('1+1') == 2);
ok(XML::LibXML::XPathContext->new($doc)->findvalue('1=2') eq 'false');

# test find()
ok(XML::LibXML::XPathContext->new($doc)->find('/foo/bar')->pop->nodeName
   eq 'bar');
ok(XML::LibXML::XPathContext->new($doc)->find('1*3')->value == '3');
ok(XML::LibXML::XPathContext->new($doc)->find('1=1')->to_literal eq 'true');

my $doc1 = XML::LibXML->new->parse_string(<<'XML');
<foo xmlns="http://example.com/foobar"><bar a="b"></bar></foo>
XML

# test registerNs()
my $xc = XML::LibXML::XPathContext->new($doc1);
$xc->registerNs('xxx', 'http://example.com/foobar');
ok($xc->findnodes('/xxx:foo')->pop->nodeName eq 'foo');

# test unregisterNs()
$xc->unregisterNs('xxx');
eval { $xc->findnodes('/xxx:foo') };
ok($@);

# test getContextNode and setContextNode
ok($xc->getContextNode->isSameNode($doc1));
$xc->setContextNode($doc1->getDocumentElement);
ok($xc->getContextNode->isSameNode($doc1->getDocumentElement));
ok($xc->findnodes('.')->pop->isSameNode($doc1->getDocumentElement));

# test xpath context preserves the document
my $xc2 = XML::LibXML::XPathContext->new(
	  XML::LibXML->new->parse_string(<<'XML'));
<foo/>
XML
ok($xc2->findnodes('*')->pop->nodeName eq 'foo');

# test xpath context preserves context node
my $doc2 = XML::LibXML->new->parse_string(<<'XML');
<foo><bar/></foo>
XML
my $xc3 = XML::LibXML::XPathContext->new($doc2->getDocumentElement);
$xc3->find('/');
ok($xc3->getContextNode->toString() eq '<foo><bar/></foo>');