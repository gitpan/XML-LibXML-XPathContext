/**
 * perl-libxml-mm.h
 * $Id: perl-libxml-mm.h,v 1.2 2003/05/20 15:25:50 pajas Exp $
 *
 * Basic concept:
 * perl varies in the implementation of UTF8 handling. this header (together
 * with the c source) implements a few functions, that can be used from within
 * the core module inorder to avoid cascades of c pragmas
 */

#ifndef __PERL_LIBXML_MM_H__
#define __PERL_LIBXML_MM_H__

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"

#include <libxml/parser.h>

#ifdef __cplusplus
}
#endif

/*
 * NAME xs_warn 
 * TYPE MACRO
 * 
 * this makro is for XML::LibXML development and debugging. 
 *
 * SYNOPSIS
 * xs_warn("my warning")
 *
 * this makro takes only a single string(!) and passes it to perls
 * warn function if the XS_WARNRINGS pragma is used at compile time
 * otherwise any xs_warn call is ignored.
 * 
 * pay attention, that xs_warn does not implement a complete wrapper
 * for warn!!
 */
#ifdef XS_WARNINGS
#define xs_warn(string) warn(string) 
#else
#define xs_warn(string)
#endif

struct _xpc_ProxyNode {
    xmlNodePtr node;
    xmlNodePtr owner;
    int count;
    int encoding;
};

/* helper type for the proxy structure */
typedef struct _xpc_ProxyNode xpc_ProxyNode;

/* pointer to the proxy structure */
typedef xpc_ProxyNode* xpc_ProxyNodePtr;

/* this my go only into the header used by the xs */
#define SvPROXYNODE(x) ((xpc_ProxyNodePtr)SvIV(SvRV(x)))
#define xpc_PmmPROXYNODE(x) ((xpc_ProxyNodePtr)x->_private)

#define xpc_PmmREFCNT(node)      node->count
#define xpc_PmmREFCNT_inc(node)  node->count++
#define xpc_PmmNODE(xnode)       xnode->node
#define xpc_PmmOWNER(node)       node->owner
#define xpc_PmmOWNERPO(node)     ((node && xpc_PmmOWNER(node)) ? (xpc_ProxyNodePtr)xpc_PmmOWNER(node)->_private : node)
#define xpc_PmmENCODING(node)    node->encoding

xpc_ProxyNodePtr
xpc_PmmNewNode(xmlNodePtr node);

xpc_ProxyNodePtr
xpc_PmmNewFragment(xmlDocPtr document);

SV*
xpc_PmmCreateDocNode( unsigned int type, xpc_ProxyNodePtr pdoc, ...);

int
xpc_PmmREFCNT_dec( xpc_ProxyNodePtr node );

SV*
xpc_PmmNodeToSv( xmlNodePtr node, xpc_ProxyNodePtr owner );

/* xpc_PmmSvNodeExt
 * TYPE 
 *    Function
 * PARAMETER
 *    @perlnode: the perl reference that holds the scalar.
 *    @copy : copy flag
 *
 * DESCRIPTION
 *
 * The function recognizes XML::LibXML and XML::GDOME 
 * nodes as valid input data. The second parameter 'copy'
 * indicates if in case of GDOME nodes the libxml2 node
 * should be copied. In some cases, where the node is 
 * cloned anyways, this flag has to be set to '0', while
 * the default value should be allways '1'. 
 */
xmlNodePtr
xpc_PmmSvNodeExt( SV * perlnode, int copy );

/* xpc_PmmSvNode
 * TYPE
 *    Macro
 * PARAMETER
 *    @perlnode: a perl reference that holds a libxml node
 *
 * DESCRIPTION
 *
 * xpc_PmmSvNode fetches the libxml node such as xpc_PmmSvNodeExt does. It is
 * a wrapper, that sets the copy always to 1, which is good for all
 * cases XML::LibXML uses.
 */
#define xpc_PmmSvNode(n) xpc_PmmSvNodeExt(n,1)


xmlNodePtr
xpc_PmmSvOwner( SV * perlnode );

SV*
xpc_PmmSetSvOwner(SV * perlnode, SV * owner );

void
xpc_PmmFixOwner(xpc_ProxyNodePtr node, xpc_ProxyNodePtr newOwner );

void
xpc_PmmFixOwnerNode(xmlNodePtr node, xpc_ProxyNodePtr newOwner );

int
xpc_PmmContextREFCNT_dec( xpc_ProxyNodePtr node );

SV*
xpc_PmmContextSv( xmlParserCtxtPtr ctxt );

xmlParserCtxtPtr
xpc_PmmSvContext( SV * perlctxt );

/**
 * NAME xpc_PmmCopyNode
 * TYPE function
 *
 * returns libxml2 node
 *
 * DESCRIPTION
 * This function implements a nodetype independant node cloning.
 * 
 * Note that this function has to stay in this module, since
 * XML::LibXSLT reuses it.
 */
xmlNodePtr
xpc_PmmCloneNode( xmlNodePtr node , int deep );

/**
 * NAME xpc_PmmNodeToGdomeSv
 * TYPE function
 *
 * returns XML::GDOME node
 *
 * DESCRIPTION
 * creates an Gdome node from our XML::LibXML node.
 * this function is very usefull for the parser.
 *
 * the function will only work, if XML::LibXML is compiled with
 * XML::GDOME support.
 *    
 */
SV *
xpc_PmmNodeToGdomeSv( xmlNodePtr node );

/**
 * NAME xpc_PmmNodeTypeName
 * TYPE function
 * 
 * returns the perl class name for the given node
 *
 * SYNOPSIS
 * CLASS = xpc_PmmNodeTypeName( node );
 */
const char*
xpc_PmmNodeTypeName( xmlNodePtr elem );

xmlChar*
xpc_PmmEncodeString( const char *encoding, const char *string );

char*
xpc_PmmDecodeString( const char *encoding, const xmlChar *string);

/* string manipulation will go elsewhere! */

/*
 * NAME c_string_to_sv
 * TYPE function
 * SYNOPSIS
 * SV *my_sv = c_string_to_sv( "my string", encoding );
 * 
 * this function converts a libxml2 string to a SV*. although the
 * string is copied, the func does not free the c-string for you!
 *
 * encoding is either NULL or a encoding string such as provided by
 * the documents encoding. if encoding is NULL UTF8 is assumed.
 *
 */
SV*
xpc_C2Sv( const xmlChar *string, const xmlChar *encoding );

/*
 * NAME sv_to_c_string
 * TYPE function
 * SYNOPSIS
 * SV *my_sv = sv_to_c_string( my_sv, encoding );
 * 
 * this function converts a SV* to a libxml string. the SV-value will
 * be copied into a *newly* allocated string. (don't forget to free it!)
 *
 * encoding is either NULL or a encoding string such as provided by
 * the documents encoding. if encoding is NULL UTF8 is assumed.
 *
 */
xmlChar *
xpc_Sv2C( SV* scalar, const xmlChar *encoding );

SV*
nodexpc_C2Sv( const xmlChar * string,  xmlNodePtr refnode );

xmlChar *
nodexpc_Sv2C( SV * scalar, xmlNodePtr refnode );

#endif
