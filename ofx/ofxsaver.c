/*
 * Jethro's finance tools
 * Copyright (C) 2014  Jethro G. Beekman
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <aqbanking/imexporter_be.h>
#include <gwenhywfar/syncio_memory.h>
#include <libofx/libofx.h>


#define WRAP(type,name,list) \
	static type (*_##name)list = NULL; \
	extern type name list

#define WRAPINIT(name) \
	if (!_##name) _##name=dlsym(RTLD_NEXT,#name); \
	if (!_##name) \
	{ \
		fprintf(stderr,"OFXSaver: Unable to resolve symbol " #name ": %s\n",dlerror()); \
		exit(1); \
	}

int g_abort=0;

static int libofx_status_cb(const struct OfxStatusData data, void *status_data)
{
	if (data.code_valid&&data.code!=0)
	{
		g_abort=1;
		fprintf(stderr,"\n====> ERROR %d - %s\n",data.code,data.name);
		if (data.code!=2000)
			fprintf(stderr,"--Description: %s\n",data.description);
		if (data.server_message_valid)
			fprintf(stderr,"--Server message: %s\n",data.server_message);
		fputc('\n',stderr);
	}
	return 0;
}

static void libofx_import(const void* buf,size_t len)
{
	LibofxContextPtr ctx=libofx_get_new_context();
	if (ctx)
	{
		ofx_set_status_cb(ctx,libofx_status_cb,NULL);
		if (0!=libofx_proc_buffer(ctx,(const char*)buf,len))
			g_abort=1;
		libofx_free_context(ctx);
	}
}

int AH_ImExporterOFXSaver_Import(AB_IMEXPORTER *ie,
			    AB_IMEXPORTER_CONTEXT *ctx,
                            GWEN_SYNCIO *sio,
			    GWEN_DB_NODE *params)
{
	fprintf(stderr,"OFXSaver<AH_ImExporterOFXSaver_Import>\n");
	
	if (strcmp(GWEN_SyncIo_GetTypeName(sio),GWEN_SYNCIO_MEMORY_TYPE)==0)
	{
		GWEN_BUFFER* buf=GWEN_SyncIo_Memory_GetBuffer(sio);
		write(3,GWEN_Buffer_GetStart(buf),GWEN_Buffer_GetUsedBytes(buf));
		libofx_import(GWEN_Buffer_GetStart(buf),GWEN_Buffer_GetUsedBytes(buf));
		write(3,"\n",1);
	}
	else
	{
		fprintf(stderr,"OFXSaver<AH_ImExporterOFXSaver_Import>: SIO not a Memory buffer, unable to extract data\n");
	}
	
	// This is the only error code that stops the retrieval process
	return g_abort?GWEN_ERROR_USER_ABORTED:0;
}

WRAP(AQBANKING_API void,AB_ImExporter_SetImportFn,(AB_IMEXPORTER *ie,AB_IMEXPORTER_IMPORT_FN f))
{
	WRAPINIT(AB_ImExporter_SetImportFn);
	
	fprintf(stderr,"OFXSaver<AB_ImExporter_SetImportFn> hook\n");
	
	_AB_ImExporter_SetImportFn(ie,&AH_ImExporterOFXSaver_Import);
}

static void module_init() __attribute__((constructor));

void module_init()
{
	if (fcntl(3,F_GETFD)==-1)
	{
		perror("OFXSaver<init> file descriptor 3");
		exit(1);
	}
}
