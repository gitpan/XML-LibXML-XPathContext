#ifndef __LIBXML_XPATH_H__
#define __LIBXML_XPATH_H__

#include <libxml/tree.h>
#include <libxml/xpath.h>

void
xpc_perlDocumentFunction( xmlXPathParserContextPtr ctxt, int nargs );

xmlNodeSetPtr
xpc_domXPathSelect( xmlXPathContextPtr ctxt, xmlChar * xpathstring );

xmlXPathObjectPtr
xpc_domXPathFind( xmlXPathContextPtr ctxt, xmlChar * xpathstring );

#endif
