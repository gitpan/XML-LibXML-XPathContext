#ifndef __LIBXML_XPATH_H__
#define __LIBXML_XPATH_H__

#include <libxml/tree.h>
#include <libxml/xpath.h>

void
perlDocumentFunction( xmlXPathParserContextPtr ctxt, int nargs );

xmlNodeSetPtr
domXPathSelect( xmlXPathContextPtr ctxt, xmlChar * xpathstring );

xmlXPathObjectPtr
domXPathFind( xmlXPathContextPtr ctxt, xmlChar * xpathstring );

#endif
