/**
 * perl-libxml-sax.h
 * $Id: perl-libxml-sax.h,v 1.2 2003/05/20 15:25:50 pajas Exp $
 */

#ifndef __PERL_LIBXML_SAX_H__
#define __PERL_LIBXML_SAX_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <libxml/tree.h>

#ifdef __cplusplus
}
#endif

/* has to be called in BOOT sequence */
void
xpc_PmmSAXInitialize();

void
xpc_PmmSAXInitContext( xmlParserCtxtPtr ctxt, SV * parser );

void 
xpc_PmmSAXCloseContext( xmlParserCtxtPtr ctxt );

xmlSAXHandlerPtr
xpc_PSaxGetHandler();

#endif
