/**
 * perl-libxml-mm.c
 * $Id: perl-libxml-mm.c,v 1.2 2003/05/20 15:25:50 pajas Exp $
 *
 * Basic concept:
 * perl varies in the implementation of UTF8 handling. this header (together
 * with the c source) implements a few functions, that can be used from within
 * the core module inorder to avoid cascades of c pragmas
 */

#ifdef __cplusplus
extern "C" {
#endif

#include <stdarg.h>
#include <stdlib.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <libxml/parser.h>
#include <libxml/tree.h>

#ifdef XML_LIBXML_GDOME_SUPPORT

#include <libgdome/gdome.h>
#include <libgdome/gdome-libxml-util.h>

#endif
#include "perl-libxml-sax.h"

#ifdef __cplusplus
}
#endif

#ifdef XS_WARNINGS
#define xs_warn(string) warn(string) 
#else
#define xs_warn(string)
#endif

/**
 * this is a wrapper function that does the type evaluation for the 
 * node. this makes the code a little more readable in the .XS
 * 
 * the code is not really portable, but i think we'll avoid some 
 * memory leak problems that way.
 **/
const char*
xpc_PmmNodeTypeName( xmlNodePtr elem ){
    const char *name = "XML::LibXML::Node";

    if ( elem != NULL ) {
        char * ptrHlp;
        switch ( elem->type ) {
        case XML_ELEMENT_NODE:
            name = "XML::LibXML::Element";   
            break;
        case XML_TEXT_NODE:
            name = "XML::LibXML::Text";
            break;
        case XML_COMMENT_NODE:
            name = "XML::LibXML::Comment";
            break;
        case XML_CDATA_SECTION_NODE:
            name = "XML::LibXML::CDATASection";
            break;
        case XML_ATTRIBUTE_NODE:
            name = "XML::LibXML::Attr"; 
            break;
        case XML_DOCUMENT_NODE:
        case XML_HTML_DOCUMENT_NODE:
            name = "XML::LibXML::Document";
            break;
        case XML_DOCUMENT_FRAG_NODE:
            name = "XML::LibXML::DocumentFragment";
            break;
        case XML_NAMESPACE_DECL:
            name = "XML::LibXML::Namespace";
            break;
        case XML_DTD_NODE:
            name = "XML::LibXML::Dtd";
            break;
        case XML_PI_NODE:
            name = "XML::LibXML::PI";
            break;
        default:
            name = "XML::LibXML::Node";
            break;
        };
        return name;
    }
    return "";
}

/*
 * @node: Reference to the node the structure proxies
 * @owner: libxml defines only the document, but not the node owner
 *         (in case of document fragments, they are not the same!)
 * @count: this is the internal reference count!
 * @encoding: this value is missing in libxml2's doc structure
 *
 * Since XML::LibXML will not know, is a certain node is already
 * defined in the perl layer, it can't shurely tell when a node can be
 * safely be removed from the memory. This structure helps to keep
 * track how intense the nodes of a document are used and will not
 * delete the nodes unless they are not refered from somewhere else.
 */
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
#define SvNAMESPACE(x) ((xmlNsPtr)SvIV(SvRV(x)))

#define xpc_PmmREFCNT(node)      node->count
#define xpc_PmmREFCNT_inc(node)  node->count++
#define xpc_PmmNODE(thenode)     thenode->node
#define xpc_PmmOWNER(node)       node->owner
#define xpc_PmmOWNERPO(node)     ((node && xpc_PmmOWNER(node)) ? (xpc_ProxyNodePtr)xpc_PmmOWNER(node)->_private : node)

#define xpc_PmmENCODING(node)    node->encoding
#define xpc_PmmNodeEncoding(node) ((xpc_ProxyNodePtr)(node->_private))->encoding

/* creates a new proxy node from a given node. this function is aware
 * about the fact that a node may already has a proxy structure.
 */
xpc_ProxyNodePtr
xpc_PmmNewNode(xmlNodePtr node)
{
    xpc_ProxyNodePtr proxy = NULL;

    if ( node == NULL ) {
        warn( "no node found\n" );
        return NULL;
    }

    if ( node->_private == NULL ) {
        proxy = (xpc_ProxyNodePtr)malloc(sizeof(struct _xpc_ProxyNode)); 
        /* proxy = (xpc_ProxyNodePtr)Newz(0, proxy, 0, xpc_ProxyNode);  */
        if (proxy != NULL) {
            proxy->node  = node;
            proxy->owner   = NULL;
            proxy->count   = 0;
            node->_private = (void*) proxy;
        }
    }
    else {
        proxy = (xpc_ProxyNodePtr)node->_private;
    }

    return proxy;
}

xpc_ProxyNodePtr
xpc_PmmNewFragment(xmlDocPtr doc) 
{
    xpc_ProxyNodePtr retval = NULL;
    xmlNodePtr frag = NULL;

    xs_warn("new frag\n");
    frag   = xmlNewDocFragment( doc );
    retval = xpc_PmmNewNode(frag);

    if ( doc ) {
        xs_warn("inc document\n");
        xpc_PmmREFCNT_inc(((xpc_ProxyNodePtr)doc->_private));
        retval->owner = (xmlNodePtr)doc;
    }

    return retval;
}

/* frees the node if nessecary. this method is aware, that libxml2
 * has several diffrent nodetypes.
 */
void
xpc_PmmFreeNode( xmlNodePtr node )
{  
    switch( node->type ) {
    case XML_DOCUMENT_NODE:
    case XML_HTML_DOCUMENT_NODE:
        xs_warn("PFN: XML_DOCUMENT_NODE\n");
        xmlFreeDoc( (xmlDocPtr) node );
        break;
    case XML_ATTRIBUTE_NODE:
        xs_warn("PFN: XML_ATTRIBUTE_NODE\n");
        if ( node->parent == NULL ) {
            xs_warn( "free node!\n");
            node->ns = NULL;
            xmlFreeProp( (xmlAttrPtr) node );
        }
        break;
    case XML_DTD_NODE:
        if ( node->doc ) {
            if ( node->doc->extSubset != (xmlDtdPtr)node 
                 && node->doc->intSubset != (xmlDtdPtr)node ) {
                xs_warn( "PFN: XML_DTD_NODE\n");
                node->doc = NULL;
                xmlFreeDtd( (xmlDtdPtr)node );
            }
        }
        break;
    case XML_DOCUMENT_FRAG_NODE:
        xs_warn("PFN: XML_DOCUMENT_FRAG_NODE\n");
    default:
        xs_warn( "PFN: normal node" );
        xmlFreeNode( node);
        break;
    }
}

/* decrements the proxy counter. if the counter becomes zero or less,
   this method will free the proxy node. If the node is part of a
   subtree, xpc_PmmREFCNT_def will fix the reference counts and delete
   the subtree if it is not required any more.
 */
int
xpc_PmmREFCNT_dec( xpc_ProxyNodePtr node ) 
{ 
    xmlNodePtr libnode = NULL;
    xpc_ProxyNodePtr owner = NULL;  
    int retval = 0;

    if ( node ) {
        retval = xpc_PmmREFCNT(node)--;
        if ( xpc_PmmREFCNT(node) <= 0 ) {
            xs_warn( "NODE DELETATION\n" );

            libnode = xpc_PmmNODE( node );
            if ( libnode != NULL ) {
                if ( libnode->_private != node ) {
                    xs_warn( "lost node\n" );
                    libnode = NULL;
                }
                else {
                    libnode->_private = NULL;
                }
            }

            xpc_PmmNODE( node ) = NULL;
            if ( xpc_PmmOWNER(node) && xpc_PmmOWNERPO(node) ) {
                xs_warn( "DOC NODE!\n" );
                owner = xpc_PmmOWNERPO(node);
                xpc_PmmOWNER( node ) = NULL;
                if( libnode != NULL && libnode->parent == NULL ) {
                    /* this is required if the node does not directly
                     * belong to the document tree
                     */
                    xs_warn( "REAL DELETE" );
                    xpc_PmmFreeNode( libnode );
                }
                xs_warn( "decrease owner" );
                xpc_PmmREFCNT_dec( owner );
            }
            else if ( libnode != NULL ) {
                xs_warn( "STANDALONE REAL DELETE" );
                
                xpc_PmmFreeNode( libnode );
            }
            /* Safefree( node ); */
            free( node );
        }
    }
    else {
        xs_warn("lost node" );
    }
    return retval;
}

/* @node: the node that should be wrapped into a SV
 * @owner: perl instance of the owner node (may be NULL)
 *
 * This function will create a real perl instance of a given node.
 * the function is called directly by the XS layer, to generate a perl
 * instance of the node. All node reference counts are updated within
 * this function. Therefore this function returns a node that can
 * directly be used as output.
 *
 * if @ower is NULL or undefined, the node is ment to be the root node
 * of the tree. this node will later be used as an owner of other
 * nodes.
 */
SV*
xpc_PmmNodeToSv( xmlNodePtr node, xpc_ProxyNodePtr owner ) 
{
    xpc_ProxyNodePtr dfProxy= NULL;
    SV * retval = &PL_sv_undef;
    const char * CLASS = "XML::LibXML::Node";

    if ( node != NULL ) {
        /* find out about the class */
        CLASS = xpc_PmmNodeTypeName( node );
        xs_warn(" return new perl node\n");
        xs_warn( CLASS );

        if ( node->_private ) {
            dfProxy = xpc_PmmNewNode(node);
        }
        else {
            dfProxy = xpc_PmmNewNode(node);
            if ( dfProxy != NULL ) {
                if ( owner != NULL ) {
                    dfProxy->owner = xpc_PmmNODE( owner );
                    xpc_PmmREFCNT_inc( owner );
                }
                else {
                   xs_warn("node contains himself");
                }
            }
            else {
                xs_warn("proxy creation failed!\n");
            }
        }

        retval = NEWSV(0,0);
        sv_setref_pv( retval, CLASS, (void*)dfProxy );
        xpc_PmmREFCNT_inc(dfProxy); 

        switch ( node->type ) {
        case XML_DOCUMENT_NODE:
        case XML_HTML_DOCUMENT_NODE:
        case XML_DOCB_DOCUMENT_NODE:
            if ( ((xmlDocPtr)node)->encoding != NULL ) {
                dfProxy->encoding = (int)xmlParseCharEncoding( (const char*)((xmlDocPtr)node)->encoding );
            }
            break;
        default:
            break;
        }
    }
    else {
        xs_warn( "no node found!" );
    }

    return retval;
}

xmlNodePtr
xpc_PmmCloneNode( xmlNodePtr node, int recursive )
{
    xmlNodePtr retval = NULL;
    
    if ( node != NULL ) {
        switch ( node->type ) {
        case XML_ELEMENT_NODE:
		case XML_TEXT_NODE:
		case XML_CDATA_SECTION_NODE:
		case XML_ENTITY_REF_NODE:
		case XML_PI_NODE:
		case XML_COMMENT_NODE:
		case XML_DOCUMENT_FRAG_NODE:
		case XML_ENTITY_DECL: 
            retval = xmlCopyNode( node, recursive );
            break;
		case XML_ATTRIBUTE_NODE:
            retval = (xmlNodePtr) xmlCopyProp( NULL, (xmlAttrPtr) node );
            break;
        case XML_DOCUMENT_NODE:
		case XML_HTML_DOCUMENT_NODE:
            retval = (xmlNodePtr) xmlCopyDoc( (xmlDocPtr)node, recursive );
            break;
        case XML_DOCUMENT_TYPE_NODE:
        case XML_DTD_NODE:
            retval = (xmlNodePtr) xmlCopyDtd( (xmlDtdPtr)node );
            break;
        case XML_NAMESPACE_DECL:
            retval = ( xmlNodePtr ) xmlCopyNamespace( (xmlNsPtr) node );
            break;
        default:
            break;
        }
    }

    return retval;
}

/* extracts the libxml2 node from a perl reference
 */

xmlNodePtr
xpc_PmmSvNodeExt( SV* perlnode, int copy ) 
{
    xmlNodePtr retval = NULL;
    xpc_ProxyNodePtr proxy = NULL;

    if ( perlnode != NULL && perlnode != &PL_sv_undef ) {
/*         if ( sv_derived_from(perlnode, "XML::LibXML::Node") */
/*              && SvPROXYNODE(perlnode) != NULL  ) { */
/*             retval = xpc_PmmNODE( SvPROXYNODE(perlnode) ) ; */
/*         } */
        xs_warn("   perlnode found\n" );
        if ( sv_derived_from(perlnode, "XML::LibXML::Node")  ) {
            proxy = SvPROXYNODE(perlnode);
            if ( proxy != NULL ) {
                xs_warn( "is a xmlNodePtr structure\n" );
                retval = xpc_PmmNODE( proxy ) ;
            }

            if ( retval != NULL
                 && ((xpc_ProxyNodePtr)retval->_private) != proxy ) {
                xs_warn( "no node in proxy node" );
                xpc_PmmNODE( proxy ) = NULL;
                retval = NULL;
            }
        }
#ifdef  XML_LIBXML_GDOME_SUPPORT
        else if ( sv_derived_from( perlnode, "XML::GDOME::Node" ) ) {
            GdomeNode* gnode = (GdomeNode*)SvIV((SV*)SvRV( perlnode ));
            if ( gnode == NULL ) {
                warn( "no XML::GDOME data found (datastructure empty)" );    
            }
            else {
                retval = gdome_xml_n_get_xmlNode( gnode );
                if ( retval == NULL ) {
                    xs_warn( "no XML::LibXML node found in GDOME object" );
                }
                else if ( copy == 1 ) {
                    retval = xpc_PmmCloneNode( retval, 1 );
                }
            }
        }
#endif
    }

    return retval;
}

/* extracts the libxml2 owner node from a perl reference
 */
xmlNodePtr
xpc_PmmSvOwner( SV* perlnode ) 
{
    xmlNodePtr retval = NULL;
    if ( perlnode != NULL
         && perlnode != &PL_sv_undef
         && SvPROXYNODE(perlnode) != NULL  ) {
        retval = xpc_PmmOWNER( SvPROXYNODE(perlnode) );
    }
    return retval;
}

/* reverse to xpc_PmmSvOwner(). sets the owner of the current node. this
 * will increase the proxy count of the owner.
 */
SV* 
xpc_PmmSetSvOwner( SV* perlnode, SV* extra )
{
    if ( perlnode != NULL && perlnode != &PL_sv_undef ) {        
        xpc_PmmOWNER( SvPROXYNODE(perlnode)) = xpc_PmmNODE( SvPROXYNODE(extra) );
        xpc_PmmREFCNT_inc( SvPROXYNODE(extra) );
    }
    return perlnode;
}

void
xpc_PmmFixOwnerList( xmlNodePtr list, xpc_ProxyNodePtr parent )
{
    if ( list ) {
        xmlNodePtr iterator = list;
        while ( iterator != NULL ) {
            switch ( iterator->type ) {
            case XML_ENTITY_DECL:
            case XML_ATTRIBUTE_DECL:
            case XML_NAMESPACE_DECL:
            case XML_ELEMENT_DECL:
                iterator = iterator->next;
                continue;
                break;
            default:
                break;
            }

            if ( iterator->_private != NULL ) {
                xpc_PmmFixOwner( (xpc_ProxyNodePtr)iterator->_private, parent );
            }
            else {
                if ( iterator->type != XML_ATTRIBUTE_NODE
                     &&  iterator->properties != NULL ){
                    xpc_PmmFixOwnerList( (xmlNodePtr)iterator->properties, parent );
                }
                xpc_PmmFixOwnerList(iterator->children, parent);
            }
            iterator = iterator->next;
        }
    }
}

/**
 * this functions fixes the reference counts for an entire subtree.
 * it is very important to fix an entire subtree after node operations
 * where the documents or the owner node may get changed. this method is
 * aware about nodes that already belong to a certain owner node. 
 *
 * the method uses the internal methods xpc_PmmFixNode and xpc_PmmChildNodes to
 * do the real updates.
 * 
 * in the worst case this traverses the subtree twice durig a node 
 * operation. this case is only given when the node has to be
 * adopted by the document. Since the ownerdocument and the effective 
 * owner may differ this double traversing makes sense.
 */ 
int
xpc_PmmFixOwner( xpc_ProxyNodePtr nodetofix, xpc_ProxyNodePtr parent ) 
{
    xpc_ProxyNodePtr oldParent = NULL;

    if ( nodetofix != NULL ) {
        switch ( xpc_PmmNODE(nodetofix)->type ) {
        case XML_ENTITY_DECL:
        case XML_ATTRIBUTE_DECL:
        case XML_NAMESPACE_DECL:
        case XML_ELEMENT_DECL:
        case XML_DOCUMENT_NODE:
            return(0);
        default:
            break;
        }

        if ( xpc_PmmOWNER(nodetofix) ) {
            oldParent = xpc_PmmOWNERPO(nodetofix);
        }
        
        /* The owner data is only fixed if the node is neither a
         * fragment nor a document. Also no update will happen if
         * the node is already his owner or the owner has not
         * changed during previous operations.
         */
        if( oldParent != parent ) {
            if ( parent && parent != nodetofix ){
                xpc_PmmOWNER(nodetofix) = xpc_PmmNODE(parent);
                    xpc_PmmREFCNT_inc( parent );
            }
            else {
                xpc_PmmOWNER(nodetofix) = NULL;
            }
            
            if ( oldParent && oldParent != nodetofix )
                xpc_PmmREFCNT_dec(oldParent);
            
            if ( xpc_PmmNODE(nodetofix)->type != XML_ATTRIBUTE_NODE
                 && xpc_PmmNODE(nodetofix)->properties != NULL ) {
                xpc_PmmFixOwnerList( (xmlNodePtr)xpc_PmmNODE(nodetofix)->properties,
                                 parent );
            }

            if ( parent == NULL || xpc_PmmNODE(nodetofix)->parent == NULL ) {
                /* fix to self */
                parent = nodetofix;
            }

            xpc_PmmFixOwnerList(xpc_PmmNODE(nodetofix)->children, parent);
        }
        else {
            xs_warn( "node doesn't need to get fixed" );
        }
        return(1);
    }
    return(0);
}

void
xpc_PmmFixOwnerNode( xmlNodePtr node, xpc_ProxyNodePtr parent )
{
    if ( node != NULL && parent != NULL ) {
        if ( node->_private != NULL ) {
            xpc_PmmFixOwner( node->_private, parent );
        }
        else {
            xpc_PmmFixOwnerList(node->children, parent );
        } 
    }
} 

xpc_ProxyNodePtr
xpc_PmmNewContext(xmlParserCtxtPtr node)
{
    xpc_ProxyNodePtr proxy = NULL;

    proxy = (xpc_ProxyNodePtr)xmlMalloc(sizeof(xpc_ProxyNode));
    if (proxy != NULL) {
        proxy->node  = (xmlNodePtr)node;
        proxy->owner   = NULL;
        proxy->count   = 1;
    }
    else {
        warn( "empty context" );
    }
    return proxy;
}
 
int
xpc_PmmContextREFCNT_dec( xpc_ProxyNodePtr node ) 
{ 
    xmlParserCtxtPtr libnode = NULL;
    int retval = 0;
    if ( node ) {
        retval = xpc_PmmREFCNT(node)--;
        if ( xpc_PmmREFCNT(node) <= 0 ) {
            xs_warn( "NODE DELETATION\n" );
            libnode = (xmlParserCtxtPtr)xpc_PmmNODE( node );
            if ( libnode != NULL ) {
                if (libnode->_private != NULL ) {
                    if ( libnode->_private != (void*)node ) {
                        xpc_PmmSAXCloseContext( libnode );
                    }
                    else {
                        xmlFree( libnode->_private );
                    }
                    libnode->_private = NULL;
                }
                xpc_PmmNODE( node )   = NULL;
                xmlFreeParserCtxt(libnode);
            }
        }
        xmlFree( node );
    }
    return retval;
}

SV*
xpc_PmmContextSv( xmlParserCtxtPtr ctxt )
{
    xpc_ProxyNodePtr dfProxy= NULL;
    SV * retval = &PL_sv_undef;
    const char * CLASS = "XML::LibXML::ParserContext";
    void * saxvector = NULL;

    if ( ctxt != NULL ) {
        dfProxy = xpc_PmmNewContext(ctxt);

        retval = NEWSV(0,0);
        sv_setref_pv( retval, CLASS, (void*)dfProxy );
        xpc_PmmREFCNT_inc(dfProxy); 
    }         
    else {
        xs_warn( "no node found!" );
    }

    return retval;
}

xmlParserCtxtPtr
xpc_PmmSvContext( SV * scalar ) 
{
    xmlParserCtxtPtr retval = NULL;

    if ( scalar != NULL
         && scalar != &PL_sv_undef
         && sv_isa( scalar, "XML::LibXML::ParserContext" )
         && SvPROXYNODE(scalar) != NULL  ) {
        retval = (xmlParserCtxtPtr)xpc_PmmNODE( SvPROXYNODE(scalar) );
    }
    else {
        if ( scalar == NULL
             && scalar == &PL_sv_undef ) {
            xs_warn( "no scalar!" );
        }
        else if ( ! sv_isa( scalar, "XML::LibXML::ParserContext" ) ) {
            xs_warn( "bad object" );
        }
        else if (SvPROXYNODE(scalar) == NULL) {
            xs_warn( "empty object" );
        }
        else {
            xs_warn( "nothing was wrong!");
        }
    }
    return retval;
}

xmlChar*
xpc_PmmFastEncodeString( int charset,
                     const xmlChar *string,
                     const xmlChar *encoding ) 
{
    xmlCharEncodingHandlerPtr coder = NULL;
    xmlChar *retval = NULL;
    xmlBufferPtr in = NULL, out = NULL;

    if ( charset == 1 ) {
        /* warn("use UTF8 for encoding ... %s ", string); */
        return xmlStrdup( string );
    }

    if ( charset > 1 ) {
        /* warn( "use document encoding %s (%d)", encoding, charset ); */
        coder= xmlGetCharEncodingHandler( charset );
    }
    else if ( charset == XML_CHAR_ENCODING_ERROR ){
        /* warn("no standard encoding %s\n", encoding); */
        coder =xmlFindCharEncodingHandler( (const char *)encoding );
    }
    else {
        xs_warn("no encoding found \n");
    }

    if ( coder != NULL ) {
        xs_warn("coding machine found \n");
        in    = xmlBufferCreate();
        out   = xmlBufferCreate();
        xmlBufferCCat( in, (const char *) string );
        if ( xmlCharEncInFunc( coder, out, in ) >= 0 ) {
            retval = xmlStrdup( out->content );
            /* warn( "encoded string is %s" , retval); */
        }
        else {
            xs_warn( "b0rked encoiding!\n");
        }
        
        xmlBufferFree( in );
        xmlBufferFree( out );
        xmlCharEncCloseFunc( coder );
    }
    return retval;
}

xmlChar*
xpc_PmmFastDecodeString( int charset,
                     const xmlChar *string,
                     const xmlChar *encoding) 
{
    xmlCharEncodingHandlerPtr coder = NULL;
    xmlChar *retval = NULL;
    xmlBufferPtr in = NULL, out = NULL;

    if ( charset == 1 ) {

        return xmlStrdup( string );
    }

    if ( charset > 1 ) {
        /* warn( "use document encoding %s", encoding ); */
        coder= xmlGetCharEncodingHandler( charset );
    }
    else if ( charset == XML_CHAR_ENCODING_ERROR ){
        /* warn("no standard encoding\n"); */
        coder = xmlFindCharEncodingHandler( (const char *) encoding );
    }
    else {
        xs_warn("no encoding found\n");
    }

    if ( coder != NULL ) {
        /* warn( "do encoding %s", string ); */
        in  = xmlBufferCreate();
        out = xmlBufferCreate();
        
        xmlBufferCat( in, string );        
        if ( xmlCharEncOutFunc( coder, out, in ) >= 0 ) {
            retval = xmlStrdup(out->content);
        }
        else {
            xs_warn("decoding error \n");
        }
        
        xmlBufferFree( in );
        xmlBufferFree( out );
        xmlCharEncCloseFunc( coder );
    }
    return retval;
}

/** 
 * encodeString returns an UTF-8 encoded String
 * while the encodig has the name of the encoding of string
 **/ 
xmlChar*
xpc_PmmEncodeString( const char *encoding, const xmlChar *string ){
    xmlCharEncoding enc;
    xmlChar *ret = NULL;
    xmlCharEncodingHandlerPtr coder = NULL;
    
    if ( string != NULL ) {
        if( encoding != NULL ) {
            xs_warn( encoding );
            enc = xmlParseCharEncoding( encoding );
            ret = xpc_PmmFastEncodeString( enc, string, (const xmlChar *)encoding );
        }
        else {
            /* if utf-8 is requested we do nothing */
            ret = xmlStrdup( string );
        }
    }
    return ret;
}

/**
 * decodeString returns an $encoding encoded string.
 * while string is an UTF-8 encoded string and 
 * encoding is the coding name
 **/
char*
xpc_PmmDecodeString( const char *encoding, const xmlChar *string){
    char *ret=NULL;
    xmlCharEncoding enc;
    xmlBufferPtr in = NULL, out = NULL;
    xmlCharEncodingHandlerPtr coder = NULL;

    if ( string != NULL ) {
        xs_warn( "xpc_PmmDecodeString called" );
        if( encoding != NULL ) {
            enc = xmlParseCharEncoding( encoding );
            ret = (char*)xpc_PmmFastDecodeString( enc, string, (const xmlChar*)encoding );
            xs_warn( "xpc_PmmDecodeString done" );
        }
        else {
            ret = (char*)xmlStrdup(string);
        }
    }
    return ret;
}


SV*
xpc_C2Sv( const xmlChar *string, const xmlChar *encoding )
{
    SV *retval = &PL_sv_undef;
    xmlCharEncoding enc;
    if ( string != NULL ) {
        if ( encoding != NULL ) {
            enc = xmlParseCharEncoding( (const char*)encoding );
        }
        else {
            enc = 0;
        }
        if ( enc == 0 ) {
            /* this happens if the encoding is "" or NULL */
            enc = XML_CHAR_ENCODING_UTF8;
        }

        if ( enc == XML_CHAR_ENCODING_UTF8 ) {
            /* create an UTF8 string. */       
            STRLEN len = 0;
            xs_warn("set UTF8 string");
            len = xmlStrlen( string );
            /* create the SV */
            /* string[len] = 0; */

            retval = NEWSV(0, len+1); 
            sv_setpvn(retval, (const char*) string, len );
#ifdef HAVE_UTF8
            xs_warn("set UTF8-SV-flag");
            SvUTF8_on(retval);
#endif            
        }
        else {
            /* just create an ordinary string. */
            xs_warn("set ordinary string");
            retval = newSVpvn( (const char *)string, xmlStrlen( string ) );
        }
    }

    return retval;
}

xmlChar *
xpc_Sv2C( SV* scalar, const xmlChar *encoding )
{
    xmlChar *retval = NULL;

    xs_warn("sv2c start!");
    if ( scalar != NULL && scalar != &PL_sv_undef ) {
        STRLEN len = 0;
        char * t_pv =SvPV(scalar, len);
        xmlChar* ts = NULL;
        xmlChar* string = xmlStrdup((xmlChar*)t_pv);
        if ( xmlStrlen(string) > 0 ) {
            xs_warn( "no undefs" );
#ifdef HAVE_UTF8
            xs_warn( "use UTF8" );
            if( !DO_UTF8(scalar) && encoding != NULL ) {
#else
            if ( encoding != NULL ) {        
#endif
                xs_warn( "xpc_domEncodeString!" );
                ts= xpc_PmmEncodeString( (const char *)encoding, string );
                xs_warn( "done!" );
                if ( string != NULL ) {
                    xmlFree(string);
                }
                string=ts;
            }
        }
             
        retval = xmlStrdup(string);
        if (string != NULL ) {
            xmlFree(string);
        }
    }
    xs_warn("sv2c end!");
    return retval;
}

SV*
nodexpc_C2Sv( const xmlChar * string,  xmlNodePtr refnode )
{
    /* this is a little helper function to avoid to much redundand
       code in LibXML.xs */
    SV* retval = &PL_sv_undef;
    STRLEN len = 0;

    if ( refnode != NULL ) {
        xmlDocPtr real_doc = refnode->doc;
        if ( real_doc && real_doc->encoding != NULL ) {

            xmlChar * decoded = xpc_PmmFastDecodeString( xpc_PmmNodeEncoding(real_doc) ,
                                                     (const xmlChar *)string,
                                                     (const xmlChar*)real_doc->encoding);
            len = xmlStrlen( decoded );

            if ( real_doc->charset == XML_CHAR_ENCODING_UTF8 ) {
                /* create an UTF8 string. */       
                xs_warn("set UTF8 string");
                /* create the SV */
                /* warn( "string is %s\n", string ); */

                retval = newSVpvn( (const char *)decoded, len );
#ifdef HAVE_UTF8
                xs_warn("set UTF8-SV-flag");
                SvUTF8_on(retval);
#endif            
            }
            else {
                /* just create an ordinary string. */
                xs_warn("set ordinary string");
                retval = newSVpvn( (const char *)decoded, len );
            }

            /* retval = xpc_C2Sv( decoded, real_doc->encoding ); */
            xmlFree( decoded );
        }
        else {
            retval = newSVpvn( (const char *)string, xmlStrlen(string) );
        }
    }
    else {
        retval = newSVpvn( (const char *)string, xmlStrlen(string) );
    }

    return retval;
}

xmlChar *
nodexpc_Sv2C( SV * scalar, xmlNodePtr refnode )
{
    /* this function requires conditionized compiling, because we
       request a function, that does not exists in earlier versions of
       perl. in this cases the library assumes, all strings are in
       UTF8. if a programmer likes to have the intelligent code, he
       needs to upgrade perl */
#ifdef HAVE_UTF8        
    if ( refnode != NULL ) {
        xmlDocPtr real_dom = refnode->doc;
        xs_warn("have node!");
        if (real_dom != NULL && real_dom->encoding != NULL ) {
            xs_warn("encode string!");
            /*  speed things a bit up.... */
            if ( scalar != NULL && scalar != &PL_sv_undef ) {
                STRLEN len = 0;
                char * t_pv =SvPV(scalar, len);
                xmlChar* ts = NULL;
                xmlChar* string = xmlStrdup((xmlChar*)t_pv);
                if ( xmlStrlen(string) > 0 ) {
                    xs_warn( "no undefs" );
#ifdef HAVE_UTF8
                    xs_warn( "use UTF8" );
                    if( !DO_UTF8(scalar) && real_dom->encoding != NULL ) {
                        xs_warn( "string is not UTF8\n" );
#else
                    if ( real_dom->encoding != NULL ) {        
#endif
                        xs_warn( "xpc_domEncodeString!" );
                        ts= xpc_PmmFastEncodeString( xpc_PmmNodeEncoding(real_dom),
                                                 string,
                                                 (const xmlChar*)real_dom->encoding );
                        xs_warn( "done!" );
                        if ( string != NULL ) {
                            xmlFree(string);
                        }
                        string=ts;
                    }
                    else {
                        xs_warn( "no encoding set, use UTF8!\n" );
                    }
                }
                if ( string == NULL ) xs_warn( "string is NULL\n" );
                return string;
            }
            else {
                xs_warn( "return NULL" );
                return NULL;
            }
        }
        else {
            xs_warn( "document has no encoding defined! use simple SV extraction\n" );
        }
    }
    xs_warn("no encoding !!");
#endif

    return  xpc_Sv2C( scalar, NULL ); 
}

SV * 
xpc_PmmNodeToGdomeSv( xmlNodePtr node ) 
{
    SV * retval = &PL_sv_undef;

#ifdef XML_LIBXML_GDOME_SUPPORT
    GdomeNode * gnode = NULL;
    GdomeException exc;
    const char * CLASS = "";

    if ( node != NULL ) {
        gnode = gdome_xml_n_mkref( node );
        if ( gnode != NULL ) {
            switch (gdome_n_nodeType(gnode, &exc)) {
            case GDOME_ELEMENT_NODE:
                CLASS = "XML::GDOME::Element";
                break;
            case GDOME_ATTRIBUTE_NODE:
                CLASS = "XML::GDOME::Attr";
                break;
            case GDOME_TEXT_NODE:
                CLASS = "XML::GDOME::Text"; 
                break;
            case GDOME_CDATA_SECTION_NODE:
                CLASS = "XML::GDOME::CDATASection"; 
                break;
            case GDOME_ENTITY_REFERENCE_NODE:
                CLASS = "XML::GDOME::EntityReference"; 
                break;
            case GDOME_ENTITY_NODE:
                CLASS = "XML::GDOME::Entity"; 
                break;
            case GDOME_PROCESSING_INSTRUCTION_NODE:
                CLASS = "XML::GDOME::ProcessingInstruction"; 
                break;
            case GDOME_COMMENT_NODE:
                CLASS = "XML::GDOME::Comment"; 
                break;
            case GDOME_DOCUMENT_TYPE_NODE:
                CLASS = "XML::GDOME::DocumentType"; 
                break;
            case GDOME_DOCUMENT_FRAGMENT_NODE:
                CLASS = "XML::GDOME::DocumentFragment"; 
                break;
            case GDOME_NOTATION_NODE:
                CLASS = "XML::GDOME::Notation"; 
                break;
            case GDOME_DOCUMENT_NODE:
                CLASS = "XML::GDOME::Document"; 
                break;
            default:
                break;
            }

            retval = NEWSV(0,0);
            sv_setref_pv( retval, CLASS, gnode);
        }
    }
#endif

    return retval;
}
