/* $Id: XPathContext.xs,v 1.42 2005/03/24 20:18:11 pajas Exp $ */

#ifdef __cplusplus
extern "C" {
#endif
#define PERL_NO_GET_CONTEXT     /* we want efficiency */

/* perl stuff */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

/* libxml2 stuff */
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

/* XML::LibXML stuff */
#include "perl-libxml-mm.h"

#include "xpath.h"

#ifdef __cplusplus
}
#endif

static SV * xpc_LibXML_error    = NULL;

/* NEWSV(0, 512); \ */
#define xpc_LibXML_init_error() if (xpc_LibXML_error == NULL || !SvOK(xpc_LibXML_error)) \
                            xpc_LibXML_error = NEWSV(0,512); \
                            sv_setpvn(xpc_LibXML_error, "", 0); \
                            xmlSetGenericErrorFunc( NULL ,  \
                                (xmlGenericErrorFunc)xpc_LibXML_error_handler);

#define xpc_LibXML_croak_error() if ( SvCUR( xpc_LibXML_error ) > 0 ) { \
                                 croak("%s",SvPV(xpc_LibXML_error, len)); \
                             } 

struct _XPathContextData {
    SV* node;
    HV* pool;  
    SV* varLookup;
    SV* varData;
};
typedef struct _XPathContextData XPathContextData;
typedef XPathContextData* XPathContextDataPtr;

#define XPathContextDATA(ctxt) ((XPathContextDataPtr) ctxt->user)


/* ****************************************************************
 * Error handler
 * **************************************************************** */

/* stores libxml errors into $@ */
static void
xpc_LibXML_error_handler(void * ctxt, const char * msg, ...)
{
    va_list args;
    SV * sv;
    dTHX;
    /* xmlParserCtxtPtr context = (xmlParserCtxtPtr) ctxt; */
    sv = NEWSV(0,512);

    va_start(args, msg);
    sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
    va_end(args);
    
    if (xpc_LibXML_error != NULL) {
        sv_catsv(xpc_LibXML_error, sv); /* remember the last error */
    }
    else {
        croak("%s",SvPV(sv, PL_na));
    }

    SvREFCNT_dec(sv);
}

/* ****************************************************************
 * Temporary node pool
 * **************************************************************** */

/* Stores pnode in context node-pool hash table in order to preserve */
/* at least one reference.                                           */
/* If pnode is NULL, only return current value for hashkey           */
static SV*
xpc_LibXML_XPathContext_pool ( xmlXPathContextPtr ctxt, int hashkey, SV * pnode ) {
    SV ** value;
    HV * pool;
    SV * key;
    SV * pnode2;
    STRLEN len;
    char * strkey;
    dTHX;

    if (XPathContextDATA(ctxt)->pool == NULL) {
        if (pnode == NULL) {
            return &PL_sv_undef;
        } else {
            xs_warn("initializing node pool");
            XPathContextDATA(ctxt)->pool = newHV();
        }
    }

    key = newSViv(hashkey);
    strkey = SvPV(key, len);
    if (pnode != NULL && !hv_exists(XPathContextDATA(ctxt)->pool,strkey,len)) {        
        value = hv_store(XPathContextDATA(ctxt)->pool,strkey,len, SvREFCNT_inc(pnode),0);
    } else {
        value = hv_fetch(XPathContextDATA(ctxt)->pool,strkey,len, 0);
    }
    SvREFCNT_dec(key);
    
    if (value == NULL) {
        return &PL_sv_undef;
    } else {
        return *value;
    }
}

/* convert perl result structures to LibXML structures */
static xmlXPathObjectPtr
xpc_LibXML_perldata_to_LibXMLdata(xmlXPathParserContextPtr ctxt,
                              SV* perl_result) {
    dTHX;
    if (!SvOK(perl_result)) {
        return (xmlXPathObjectPtr)xmlXPathNewCString("");        
    }
    if (SvROK(perl_result) &&
        SvTYPE(SvRV(perl_result)) == SVt_PVAV) {
        /* consider any array ref to be a nodelist */
        int i;
        int length;
        SV ** pnode;
        AV * array_result;
        xmlXPathObjectPtr ret;

        ret = (xmlXPathObjectPtr) xmlXPathNewNodeSet((xmlNodePtr) NULL);
        array_result = (AV*)SvRV(perl_result);
        length = av_len(array_result);
        for( i = 0; i <= length ; i++ ) {
            pnode = av_fetch(array_result,i,0);
            if (pnode != NULL && sv_isobject(*pnode) &&
                sv_derived_from(*pnode,"XML::LibXML::Node")) {
                xmlXPathNodeSetAdd(ret->nodesetval, 
                                   (xmlNodePtr)xpc_PmmSvNode(*pnode));
                if(ctxt) {
                    xpc_LibXML_XPathContext_pool(ctxt->context,
                                             (int) xpc_PmmSvNode(*pnode), *pnode);
                }
            } else {
                warn("XPathContext: ignoring non-node member of a nodelist");
            }
        }
        return ret;
    } else if (sv_isobject(perl_result) && 
               (SvTYPE(SvRV(perl_result)) == SVt_PVMG)) 
        {
            if (sv_derived_from(perl_result, "XML::LibXML::Node")) {
                xmlNodePtr tmp_node;
                xmlXPathObjectPtr ret;

                ret =  (xmlXPathObjectPtr)xmlXPathNewNodeSet(NULL);
                tmp_node = (xmlNodePtr)xpc_PmmSvNode(perl_result);
                xmlXPathNodeSetAdd(ret->nodesetval,tmp_node);
                if(ctxt) {
                    xpc_LibXML_XPathContext_pool(ctxt->context, (int) xpc_PmmSvNode(perl_result), 
                                             perl_result);
                }

                return ret;
            }
            else if (sv_isa(perl_result, "XML::LibXML::Boolean")) {
                return (xmlXPathObjectPtr)
                    xmlXPathNewBoolean(SvIV(SvRV(perl_result)));
            }
            else if (sv_isa(perl_result, "XML::LibXML::Literal")) {
                return (xmlXPathObjectPtr)
                    xmlXPathNewCString(SvPV_nolen(SvRV(perl_result)));
            }
            else if (sv_isa(perl_result, "XML::LibXML::Number")) {
                return (xmlXPathObjectPtr)
                    xmlXPathNewFloat(SvNV(SvRV(perl_result)));
            }
        } else if (SvNOK(perl_result) || SvIOK(perl_result)) {
            return (xmlXPathObjectPtr)xmlXPathNewFloat(SvNV(perl_result));
        } else {
            return (xmlXPathObjectPtr)
                xmlXPathNewCString(SvPV_nolen(perl_result));
        }
}


/* save XPath context and XPathContextDATA for recursion */
static xmlXPathContextPtr
xpc_LibXML_save_context(xmlXPathContextPtr ctxt)
{
    xmlXPathContextPtr copy;
    copy = xmlMalloc(sizeof(xmlXPathContext));
    if (copy) {
	/* backup ctxt */
	memcpy(copy, ctxt, sizeof(xmlXPathContext));
	/* clear namespaces so that they are not freed and overwritten
	   by configure_namespaces */
	ctxt->namespaces = NULL;
	/* backup data */
	copy->user = xmlMalloc(sizeof(XPathContextData));
	if (XPathContextDATA(copy)) {
	    memcpy(XPathContextDATA(copy), XPathContextDATA(ctxt),sizeof(XPathContextData));
	    /* clear ctxt->pool, so that it is not used freed during re-entrance */
	    XPathContextDATA(ctxt)->pool = NULL; 
	}
    }
    return copy;
}

/* restore XPath context and XPathContextDATA from a saved copy */
static void
xpc_LibXML_restore_context(xmlXPathContextPtr ctxt, xmlXPathContextPtr copy)
{
    dTHX;
    /* cleanup */
    if (XPathContextDATA(ctxt)) {
	/* cleanup newly created pool */
	if (XPathContextDATA(ctxt)->pool != NULL &&
	    SvOK(XPathContextDATA(ctxt)->pool)) {
	    SvREFCNT_dec((SV *)XPathContextDATA(ctxt)->pool);
	}
    }
    if (ctxt->namespaces) {
	/* free namespaces allocated during recursion */
        xmlFree( ctxt->namespaces );
    }

    /* restore context */
    if (copy) {
	/* 1st restore our data */
	if (XPathContextDATA(copy)) {
	    memcpy(XPathContextDATA(ctxt),XPathContextDATA(copy),sizeof(XPathContextData));
	    xmlFree(XPathContextDATA(copy));
	    copy->user = XPathContextDATA(ctxt);
	}
	/* now copy the rest */
	memcpy(ctxt, copy, sizeof(xmlXPathContext));
	xmlFree(copy);
    }
}


/* ****************************************************************
 * Variable Lookup
 * **************************************************************** */
/* Much of the code is borrowed from Matt Sergeant's XML::LibXSLT   */
static xmlXPathObjectPtr
xpc_LibXML_generic_variable_lookup(void* varLookupData,
                               const xmlChar *name,
                               const xmlChar *ns_uri)
{
    xmlXPathObjectPtr ret;
    xmlXPathContextPtr ctxt;
    xmlXPathContextPtr copy;
    XPathContextDataPtr data;
    I32 count;
    dTHX;
    dSP;

    ctxt = (xmlXPathContextPtr) varLookupData;
    if ( ctxt == NULL )
	croak("XPathContext: missing xpath context");
    data = XPathContextDATA(ctxt);
    if ( data == NULL )
	croak("XPathContext: missing xpath context private data");
    if ( data->varLookup == NULL || !SvROK(data->varLookup) || 
	 SvTYPE(SvRV(data->varLookup)) != SVt_PVCV )
        croak("XPathContext: lost variable lookup function!");

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs( (data->varData != NULL) ? data->varData : &PL_sv_undef ); 
    XPUSHs(sv_2mortal(xpc_C2Sv(name,NULL))); 
    XPUSHs(sv_2mortal(xpc_C2Sv(ns_uri,NULL)));

    /* save context to allow recursive usage of XPathContext */
    copy = xpc_LibXML_save_context(ctxt);

    PUTBACK ;    
    count = perl_call_sv(data->varLookup, G_SCALAR|G_EVAL);
    SPAGAIN;

    /* restore the xpath context */
    xpc_LibXML_restore_context(ctxt, copy);

    if (SvTRUE(ERRSV)) {
        POPs;
        croak("XPathContext: error coming back from variable lookup function. %s", SvPV_nolen(ERRSV));
    } 
    if (count != 1) croak("XPathContext: variable lookup function returned more than one argument!");

    ret = xpc_LibXML_perldata_to_LibXMLdata(NULL, POPs);

    PUTBACK;
    FREETMPS;
    LEAVE;    
    return ret;
}

/* ****************************************************************
 * Generic Extension Function
 * **************************************************************** */
/* Much of the code is borrowed from Matt Sergeant's XML::LibXSLT   */
static void
xpc_LibXML_generic_extension_function(xmlXPathParserContextPtr ctxt, int nargs) 
{
    xmlXPathObjectPtr obj,ret;
    xmlNodeSetPtr nodelist = NULL;
    int count;
    SV * perl_dispatch;
    int i;
    STRLEN len;
    xpc_ProxyNodePtr owner = NULL;
    SV *key;
    char *strkey;
    const char *function, *uri;
    SV **perl_function;
    dTHX;
    dSP;
    SV * data;
    xmlXPathContextPtr copy;

    /* warn("entered xpc_LibXML_generic_extension_function for %s\n",ctxt->context->function); */
    data = (SV *) ctxt->context->funcLookupData;
    if (ctxt->context->funcLookupData == NULL || !SvROK(data) ||
        SvTYPE(SvRV(data)) != SVt_PVHV) {
        croak("XPathContext: lost function lookup data structure!");
    }
    
    function = ctxt->context->function;
    uri = ctxt->context->functionURI;
    
    key = newSVpvn("",0);
    if (uri && *uri) {
        sv_catpv(key, "{");
        sv_catpv(key, (const char*)uri);
        sv_catpv(key, "}");
    }
    sv_catpv(key, (const char*)function);
    strkey = SvPV(key, len);
    perl_function =
        hv_fetch((HV*)SvRV(data), strkey, len, 0);
    if ( perl_function == NULL || !SvOK(*perl_function) || 
         !(SvPOK(*perl_function) ||
           (SvROK(*perl_function) &&
            SvTYPE(SvRV(*perl_function)) == SVt_PVCV))) {
        croak("XPathContext: lost perl extension function!");
    }
    SvREFCNT_dec(key);

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    
    XPUSHs(*perl_function);

    /* set up call to perl dispatcher function */
    for (i = 0; i < nargs; i++) {
        obj = (xmlXPathObjectPtr)valuePop(ctxt);
        switch (obj->type) {
        case XPATH_XSLT_TREE:
        case XPATH_NODESET:
            nodelist = obj->nodesetval;
            if ( nodelist ) {
                XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));                
                XPUSHs(sv_2mortal(newSViv(nodelist->nodeNr)));
                if ( nodelist->nodeNr > 0 ) {
                    int j = 0 ;
                    const char * cls = "XML::LibXML::Node";
                    xmlNodePtr tnode;
                    SV * element;

                    len = nodelist->nodeNr;
                    for( j ; j < len; j++){
                        tnode = nodelist->nodeTab[j];
                        if( tnode != NULL && tnode->doc != NULL) {
                            owner = xpc_PmmOWNERPO(xpc_PmmNewNode((xmlNodePtr) tnode->doc));
                        } else {
                            owner = NULL;
                        }
                        if (tnode->type == XML_NAMESPACE_DECL) {
                            element = sv_newmortal();
                            cls = xpc_PmmNodeTypeName( tnode );
                            element = sv_setref_pv( element,
                                                    (const char *)cls,
                                                    (void *)xmlCopyNamespace((xmlNsPtr)tnode)
                                );
                        }
                        else {
                            element = xpc_PmmNodeToSv(tnode, owner);
                        }
                        XPUSHs( sv_2mortal(element) );
                    }
                }
            } else {
                /* PP: We can't simply leave out an empty nodelist as Matt does! */
                /* PP: The number of arguments must match! */
                XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));                
                XPUSHs(sv_2mortal(newSViv(0)));
            }
            /* prevent libxml2 from freeing the actual nodes */
            if (obj->boolval) obj->boolval=0;
            break;
        case XPATH_BOOLEAN:
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Boolean", 0)));
            XPUSHs(sv_2mortal(newSViv(obj->boolval)));
            break;
        case XPATH_NUMBER:
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Number", 0)));
            XPUSHs(sv_2mortal(newSVnv(obj->floatval)));
            break;
        case XPATH_STRING:
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
            XPUSHs(sv_2mortal(xpc_C2Sv(obj->stringval, 0)));
            break;
        default:
            warn("Unknown XPath return type (%d) in call to {%s}%s - assuming string", obj->type, uri, function);
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
            XPUSHs(sv_2mortal(xpc_C2Sv((char*)xmlXPathCastToString(obj), 0)));
        }
        xmlXPathFreeObject(obj);
    }

    /* save context to allow recursive usage of XPathContext */
    copy = xpc_LibXML_save_context(ctxt->context);

    /* call perl dispatcher */
    PUTBACK;
    perl_dispatch = sv_2mortal(newSVpv("XML::LibXML::XPathContext::_perl_dispatcher",0));
    count = perl_call_sv(perl_dispatch, G_SCALAR|G_EVAL);    
    SPAGAIN;

    /* restore the xpath context */
    xpc_LibXML_restore_context(ctxt->context, copy);
    
    if (SvTRUE(ERRSV)) {
        POPs;
        croak("XPathContext: error coming back from perl-dispatcher in pm file. %s", SvPV_nolen(ERRSV));
    } 

    if (count != 1) croak("XPathContext: perl-dispatcher in pm file returned more than one argument!");
    
    ret = xpc_LibXML_perldata_to_LibXMLdata(ctxt, POPs);

    valuePush(ctxt, ret);
    PUTBACK;
    FREETMPS;
    LEAVE;    
}

static void
xpc_LibXML_configure_namespaces( xmlXPathContextPtr ctxt ) {
    xmlNodePtr node = ctxt->node;

    if (ctxt->namespaces != NULL) {
        xmlFree( ctxt->namespaces );
        ctxt->namespaces = NULL;
    }
    if (node != NULL) {
        if (node->type == XML_DOCUMENT_NODE) {
            ctxt->namespaces = xmlGetNsList( node->doc,
                                             xmlDocGetRootElement( node->doc ) );
        } else {
            ctxt->namespaces = xmlGetNsList(node->doc, node);
        }
        ctxt->nsNr = 0;
        if (ctxt->namespaces != NULL) {
            while (ctxt->namespaces[ctxt->nsNr] != NULL)
                ctxt->nsNr++;
        }
    }
}

static void
xpc_LibXML_configure_xpathcontext( xmlXPathContextPtr ctxt ) {
    xmlNodePtr node = xpc_PmmSvNode(XPathContextDATA(ctxt)->node);

    if (node != NULL) {    
        ctxt->doc = node->doc;
    } else {
        ctxt->doc = NULL;
    }
    ctxt->node = node;

    xpc_LibXML_configure_namespaces(ctxt);
}

MODULE = XML::LibXML::XPathContext     PACKAGE = XML::LibXML::XPathContext

PROTOTYPES: DISABLE

SV*
new( CLASS, ... )
        const char * CLASS
    PREINIT:
        SV * pnode = &PL_sv_undef;
    INIT:
        xmlXPathContextPtr ctxt;
    CODE:
        if( items > 1 )
            pnode = ST(1);

        ctxt = xmlXPathNewContext( NULL );
        ctxt->namespaces = NULL;

        New(0, ctxt->user, sizeof(XPathContextData), XPathContextData);
        if (ctxt->user == NULL) {
            croak("XPathContext: failed to allocate proxy object");
        } 

        if (SvOK(pnode)) {
          XPathContextDATA(ctxt)->node = newSVsv(pnode); 
        } else {
          XPathContextDATA(ctxt)->node = &PL_sv_undef;
        }

        XPathContextDATA(ctxt)->pool = NULL;
        XPathContextDATA(ctxt)->varLookup = NULL;
        XPathContextDATA(ctxt)->varData = NULL;

        xmlXPathRegisterFunc(ctxt,
                             (const xmlChar *) "document",
                             xpc_perlDocumentFunction);

        RETVAL = NEWSV(0,0),
        RETVAL = sv_setref_pv( RETVAL,
                               CLASS,
                               (void*)ctxt );
    OUTPUT:
        RETVAL

void
DESTROY( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
    CODE:
        xs_warn( "DESTROY XPATH CONTEXT" );
        if (ctxt) {
            if (XPathContextDATA(ctxt) != NULL) {
                if (XPathContextDATA(ctxt)->node != NULL &&
                    SvOK(XPathContextDATA(ctxt)->node)) {
                    SvREFCNT_dec(XPathContextDATA(ctxt)->node);
                }
                if (XPathContextDATA(ctxt)->varLookup != NULL &&
                    SvOK(XPathContextDATA(ctxt)->varLookup)) {
                    SvREFCNT_dec(XPathContextDATA(ctxt)->varLookup);
                }
                if (XPathContextDATA(ctxt)->varData != NULL &&
                    SvOK(XPathContextDATA(ctxt)->varData)) {
                    SvREFCNT_dec(XPathContextDATA(ctxt)->varData);
                }
                if (XPathContextDATA(ctxt)->pool != NULL &&
                    SvOK(XPathContextDATA(ctxt)->pool)) {
                    SvREFCNT_dec((SV *)XPathContextDATA(ctxt)->pool);
                }
                Safefree(XPathContextDATA(ctxt));
            }

            if (ctxt->namespaces != NULL) {
                xmlFree( ctxt->namespaces );
            }
            if (ctxt->funcLookupData != NULL && SvROK((SV*)ctxt->funcLookupData)
                && SvTYPE(SvRV((SV *)ctxt->funcLookupData)) == SVt_PVHV) {
                SvREFCNT_dec((SV *)ctxt->funcLookupData);
            }
            
            xmlXPathFreeContext(ctxt);
        }

SV*
getContextNode( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    CODE:
        if(XPathContextDATA(ctxt)->node != NULL) {
            RETVAL = newSVsv(XPathContextDATA(ctxt)->node);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int
getContextPosition( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    CODE:
        RETVAL = ctxt->proximityPosition;
    OUTPUT:
	RETVAL

int
getContextSize( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    CODE:
        RETVAL = ctxt->contextSize;
    OUTPUT:
	RETVAL

void 
setContextNode( self , pnode )
        SV * self
        SV * pnode
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    PPCODE:
        if (XPathContextDATA(ctxt)->node != NULL) {
            SvREFCNT_dec(XPathContextDATA(ctxt)->node);
        }
        if (SvOK(pnode)) {
            XPathContextDATA(ctxt)->node = newSVsv(pnode);
        } else {
            XPathContextDATA(ctxt)->node = NULL;
        }

void 
setContextPosition( self , position )
        SV * self
        int position
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL )
            croak("XPathContext: missing xpath context");
        if ( position < -1 || position > ctxt->contextSize )
	    croak("XPathContext: invalid position");
    PPCODE:
        ctxt->proximityPosition = position;

void 
setContextSize( self , size )
        SV * self
        int size
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL )
            croak("XPathContext: missing xpath context");
        if ( size < -1 )
	    croak("XPathContext: invalid size");
    PPCODE:
        ctxt->contextSize = size;
        if ( size == 0 )
	    ctxt->proximityPosition = 0;
	else if ( size > 0 )
	    ctxt->proximityPosition = 1;
        else 
	    ctxt->proximityPosition = -1;

void
registerNs( pxpath_context, prefix, ns_uri )
        SV * pxpath_context
        SV * prefix
        SV * ns_uri
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        int ret = -1;
    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
        xpc_LibXML_configure_xpathcontext(ctxt);
    PPCODE:
        if(SvOK(ns_uri)) {
            if(xmlXPathRegisterNs(ctxt, SvPV_nolen(prefix),
                                  SvPV_nolen(ns_uri)) == -1) {
                croak("XPathContext: cannot register namespace");
            }
        } else {
            if(xmlXPathRegisterNs(ctxt, SvPV_nolen(prefix), NULL) == -1) {
                croak("XPathContext: cannot unregister namespace");
            }
        }

SV*
lookupNs( pxpath_context, prefix )
        SV * pxpath_context
        SV * prefix
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
        xpc_LibXML_configure_xpathcontext(ctxt);
    CODE:
        RETVAL = xpc_C2Sv(xmlXPathNsLookup(ctxt, SvPV_nolen(prefix)), NULL);
    OUTPUT:
        RETVAL

SV*
getVarLookupData( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    CODE:
        if(XPathContextDATA(ctxt)->varData != NULL) {
            RETVAL = newSVsv(XPathContextDATA(ctxt)->varData);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV*
getVarLookupFunc( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = (xmlXPathContextPtr)SvIV(SvRV(self)); 
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    CODE:
        if(XPathContextDATA(ctxt)->varData != NULL) {
            RETVAL = newSVsv(XPathContextDATA(ctxt)->varLookup);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

void
registerVarLookupFunc( pxpath_context, lookup_func, lookup_data )
        SV * pxpath_context
        SV * lookup_func
        SV * lookup_data
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        XPathContextDataPtr data = NULL;
        SV* pfdr;
    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL )
            croak("XPathContext: missing xpath context");
        data = XPathContextDATA(ctxt);
        if ( data == NULL )
            croak("XPathContext: missing xpath context private data");
        xpc_LibXML_configure_xpathcontext(ctxt);
        /* free previous lookup function and data */
        if (data->varLookup && SvOK(data->varLookup))
            SvREFCNT_dec(data->varLookup);
        if (data->varData && SvOK(data->varData))
            SvREFCNT_dec(data->varData);
        data->varLookup=NULL;
        data->varData=NULL;
    PPCODE:
        if (SvOK(lookup_func)) {
            if ( SvROK(lookup_func) && SvTYPE(SvRV(lookup_func)) == SVt_PVCV ) {
		data->varLookup = newSVsv(lookup_func);
		if (SvOK(lookup_data)) 
		    data->varData = newSVsv(lookup_data);
		xmlXPathRegisterVariableLookup(ctxt, 
					       xpc_LibXML_generic_variable_lookup, ctxt);
		if (ctxt->varLookupData==NULL || ctxt->varLookupData != ctxt) {
		    croak( "XPathContext: registration failure" );
		}    
            } else {
                croak("XPathContext: 1st argument is not a CODE reference");
            }
        } else {
            /* unregister */
            xmlXPathRegisterVariableLookup(ctxt, NULL, NULL);
        }

void
registerFunctionNS( pxpath_context, name, uri, func)
        SV * pxpath_context
        char * name
        SV * uri
        SV * func
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        SV * pfdr;
        SV * key;
        STRLEN len;
        char *strkey;

    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
        xpc_LibXML_configure_xpathcontext(ctxt);
        if ( !SvOK(func) || SvOK(func) && 
             ((SvROK(func) && SvTYPE(SvRV(func)) == SVt_PVCV ) || SvPOK(func))) {
            if (ctxt->funcLookupData == NULL) {
                if (SvOK(func)) {
                    pfdr = newRV_inc((SV*) newHV());
                    ctxt->funcLookupData = pfdr;
                } else {
                    /* looks like no perl function was never registered, */
                    /* nothing to unregister */
                    warn("XPathContext: nothing to unregister");
                    return;
                }
            } else {
                if (SvTYPE(SvRV((SV *)ctxt->funcLookupData)) == SVt_PVHV) {
                    /* good, it's a HV */
                    pfdr = (SV *)ctxt->funcLookupData;
                } else {
                    croak ("XPathContext: cannot register: funcLookupData structure occupied");
                }
            }
            key = newSVpvn("",0);
            if (SvOK(uri)) {
                sv_catpv(key, "{");
                sv_catsv(key, uri);
                sv_catpv(key, "}");
            }
            sv_catpv(key, (const char*)name);
            strkey = SvPV(key, len);
            /* warn("Trying to store function '%s' in %d\n", strkey, pfdr); */
            if (SvOK(func)) {
                hv_store((HV *)SvRV(pfdr),strkey, len, newSVsv(func), 0);
            } else {
                /* unregister */
                hv_delete((HV *)SvRV(pfdr),strkey, len, G_DISCARD);
            }
            SvREFCNT_dec(key);
        } else {
            croak("XPathContext: 3rd argument is not a CODE reference or function name");
        }
    PPCODE:
        if (SvOK(uri)) {
            xmlXPathRegisterFuncNS(ctxt, name, SvPV(uri, len), 
                                   (SvOK(func) ? 
                                    xpc_LibXML_generic_extension_function : NULL));
        } else {    
            xmlXPathRegisterFunc(ctxt, name, 
                                 (SvOK(func) ? 
                                  xpc_LibXML_generic_extension_function : NULL));
        }

void
_free_node_pool( pxpath_context )
        SV * pxpath_context
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
    PPCODE:
        if (XPathContextDATA(ctxt)->pool != NULL) {
            SvREFCNT_dec((SV *)XPathContextDATA(ctxt)->pool);
            XPathContextDATA(ctxt)->pool = NULL;
        }

void
_findnodes( pxpath_context, perl_xpath )
        SV * pxpath_context
        SV * perl_xpath 
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        xpc_ProxyNodePtr owner = NULL;
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV * element = NULL ;
        STRLEN len = 0 ;
        xmlChar * xpath = NULL;
    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
        xpc_LibXML_configure_xpathcontext(ctxt);
        if ( ctxt->node == NULL ) {
            croak("XPathContext: lost current node");
        }
        xpath = nodexpc_Sv2C(perl_xpath, ctxt->node);
        if ( !(xpath && xmlStrlen(xpath)) ) {
            if ( xpath ) 
                xmlFree(xpath);
            croak("XPathContext: empty XPath found");
            XSRETURN_UNDEF;
        }
    PPCODE:
        if ( ctxt->node->doc ) {
            xpc_domNodeNormalize( xmlDocGetRootElement(ctxt->node->doc) );
        }
        else {
            xpc_domNodeNormalize( xpc_PmmOWNER(xpc_PmmNewNode(ctxt->node)) );
        }

        xpc_LibXML_init_error();

        PUTBACK ;
        found = xpc_domXPathFind( ctxt, xpath );
        SPAGAIN ;

        if (found != NULL) {
          nodelist = found->nodesetval;  
        } else {
          nodelist = NULL;
        }
        xmlFree(xpath);

        xpc_LibXML_croak_error();

        if ( nodelist ) {
            if ( nodelist->nodeNr > 0 ) {
                int i = 0 ;
                const char * cls = "XML::LibXML::Node";
                xmlNodePtr tnode;
                len = nodelist->nodeNr;
                for( i ; i < len; i++){
                    /* we have to create a new instance of an objectptr. 
                     * and then place the current node into the new object. 
                     * afterwards we can push the object to the array!
                     */ 
                    element = NULL;
                    tnode = nodelist->nodeTab[i];
                    if (tnode->type == XML_NAMESPACE_DECL) {
                        xmlNsPtr newns = xmlCopyNamespace((xmlNsPtr)tnode);
                        if ( newns != NULL ) {
                            element = NEWSV(0,0);
                            cls = xpc_PmmNodeTypeName( tnode );
                            element = sv_setref_pv( element,
                                                    (const char *)cls,
                                                    newns
                                                  );
                        }
                        else {
                            continue;
                        }
                    }
                    else {
                        if (tnode->doc) {
                            owner = xpc_PmmOWNERPO(xpc_PmmNewNode((xmlNodePtr) tnode->doc));
                        } else {
                            owner = NULL; /* self contained node */
                        }
                        element = xpc_PmmNodeToSv(tnode, owner);
                    }
                    XPUSHs( sv_2mortal(element) );
                }
            }
            /* prevent libxml2 from freeing the actual nodes */
            if (found->boolval) found->boolval=0;
            xmlXPathFreeObject(found);
        }
        else {
            xmlXPathFreeObject(found);
            xpc_LibXML_croak_error();
        }

void
_find( pxpath_context, pxpath )
        SV * pxpath_context
        SV * pxpath
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        xpc_ProxyNodePtr owner = NULL;
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV* element = NULL ;
        STRLEN len = 0 ;
        xmlChar * xpath = NULL;
    INIT:
        ctxt = (xmlXPathContextPtr)SvIV(SvRV(pxpath_context));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context");
        }
        xpc_LibXML_configure_xpathcontext(ctxt);
        if ( ctxt->node == NULL ) {
            croak("XPathContext: lost current node");
        }
        xpath = nodexpc_Sv2C(pxpath, ctxt->node);
        if ( !(xpath && xmlStrlen(xpath)) ) {
            if ( xpath ) 
                xmlFree(xpath);
            croak("XPathContext: empty XPath found");
            XSRETURN_UNDEF;
        }

    PPCODE:
        if ( ctxt->node->doc ) {
            xpc_domNodeNormalize( xmlDocGetRootElement( ctxt->node->doc ) );
        }
        else {
            xpc_domNodeNormalize( xpc_PmmOWNER(xpc_PmmNewNode(ctxt->node)) );
        }

        xpc_LibXML_init_error();

        PUTBACK ;
        found = xpc_domXPathFind( ctxt, xpath );
        SPAGAIN ;

        xmlFree( xpath );

        xpc_LibXML_croak_error();

        if (found) {
            switch (found->type) {
                case XPATH_NODESET:
                    /* return as a NodeList */
                    /* access ->nodesetval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));
                    nodelist = found->nodesetval;
                    if ( nodelist ) {
                        if ( nodelist->nodeNr > 0 ) {
                            int i = 0 ;
                            const char * cls = "XML::LibXML::Node";
                            xmlNodePtr tnode;
                            SV * element;
                        
                            len = nodelist->nodeNr;
                            for( i ; i < len; i++){
                                /* we have to create a new instance of an
                                 * objectptr. and then
                                 * place the current node into the new
                                 * object. afterwards we can
                                 * push the object to the array!
                                 */
                                tnode = nodelist->nodeTab[i];

                                /* let's be paranoid */
                                if (tnode->type == XML_NAMESPACE_DECL) {
                                     xmlNsPtr newns = xmlCopyNamespace((xmlNsPtr)tnode);
                                    if ( newns != NULL ) {
                                        element = NEWSV(0,0);
                                        cls = xpc_PmmNodeTypeName( tnode );
                                        element = sv_setref_pv( element,
                                                                (const char *)cls,
                                                                (void*)newns
                                                          );
                                    }
                                    else {
                                        continue;
                                    }
                                }
                                else {
                                    if (tnode->doc) {
                                        owner = xpc_PmmOWNERPO(xpc_PmmNewNode((xmlNodePtr) tnode->doc));
                                    } else {
                                        owner = NULL; /* self contained node */
                                    }
                                    element = xpc_PmmNodeToSv(tnode, owner);
                                }
                                XPUSHs( sv_2mortal(element) );
                            }
                        }
                    }
                    /* prevent libxml2 from freeing the actual nodes */
                    if (found->boolval) found->boolval=0;    
                    break;
                case XPATH_BOOLEAN:
                    /* return as a Boolean */
                    /* access ->boolval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Boolean", 0)));
                    XPUSHs(sv_2mortal(newSViv(found->boolval)));
                    break;
                case XPATH_NUMBER:
                    /* return as a Number */
                    /* access ->floatval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Number", 0)));
                    XPUSHs(sv_2mortal(newSVnv(found->floatval)));
                    break;
                case XPATH_STRING:
                    /* access ->stringval */
                    /* return as a Literal */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
                    XPUSHs(sv_2mortal(xpc_C2Sv(found->stringval, NULL)));
                    break;
                default:
                    croak("Unknown XPath return type");
            }
            xmlXPathFreeObject(found);
        }
        else {
            xpc_LibXML_croak_error();
        }
