<%
/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file 
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
%>
<%@ page
contentType="text/html; charset=UTF-8"
	import="javax.servlet.*"
	import="javax.servlet.http.*"
	import="java.io.*"
	import="java.util.*"
	import="org.apache.hadoop.fs.*"
	import="org.apache.hadoop.hdfs.*"
	import="org.apache.hadoop.hdfs.server.common.*"
	import="org.apache.hadoop.hdfs.server.namenode.*"
	import="org.apache.hadoop.hdfs.server.datanode.*"
	import="org.apache.hadoop.hdfs.protocol.*"
	import="org.apache.hadoop.util.*"
	import="java.text.DateFormat"
	import="java.lang.Math"
	import="java.net.URLEncoder"
%>
<%!
	int rowNum = 0;
	int colNum = 0;

	String rowTxt() { colNum = 0;
	return "<tr class=\"" + (((rowNum++)%2 == 0)? "rowNormal" : "rowAlt")
	+ "\"> "; }
	String colTxt() { return "<td id=\"col" + ++colNum + "\"> "; }
	void counterReset () { colNum = 0; rowNum = 0 ; }

	long diskBytes = 1024 * 1024 * 1024;
	String diskByteStr = "GB";

	String sorterField = null;
	String sorterOrder = null;
	String whatNodes = "LIVE";

String NodeHeaderStr(String name) {
	String ret = "class=header";
	String order = "ASC";
	if ( name.equals( sorterField ) ) {
		ret += sorterOrder;
		if ( sorterOrder.equals("ASC") )
			order = "DSC";
	}
	ret += " onClick=\"window.document.location=" +
	"'/dfsnodelist.jsp?whatNodes="+whatNodes+"&sorter/field=" + name + "&sorter/order=" +
	order + "'\" title=\"sort on this column\"";

	return ret;
}

public void generateNodeData( JspWriter out, DatanodeDescriptor d,
		String suffix, boolean alive,
		int nnHttpPort )
throws IOException {

	/* Say the datanode is dn1.hadoop.apache.org with ip 192.168.0.5
we use:
1) d.getHostName():d.getPort() to display.
Domain and port are stripped if they are common across the nodes.
i.e. "dn1"
2) d.getHost():d.Port() for "title".
i.e. "192.168.0.5:50010"
3) d.getHostName():d.getInfoPort() for url.
i.e. "http://dn1.hadoop.apache.org:50075/..."
Note that "d.getHost():d.getPort()" is what DFS clients use
to interact with datanodes.
	 */
	// from nn_browsedfscontent.jsp:
	String url = "http://" + d.getHostName() + ":" + d.getInfoPort() +
	"/browseDirectory.jsp?namenodeInfoPort=" +
	nnHttpPort + "&dir=" +
	URLEncoder.encode("/", "UTF-8");

	String name = d.getHostName() + ":" + d.getPort();
	if ( !name.matches( "\\d+\\.\\d+.\\d+\\.\\d+.*" ) ) 
		name = name.replaceAll( "\\.[^.:]*", "" );    
	int idx = (suffix != null && name.endsWith( suffix )) ?
			name.indexOf( suffix ) : -1;

			out.print( rowTxt() + "<td class=\"name\"><a title=\""
					+ d.getHost() + ":" + d.getPort() +
					"\" href=\"" + url + "\">" +
					(( idx > 0 ) ? name.substring(0, idx) : name) + "</a>" +
					(( alive ) ? "" : "\n") );
			if ( !alive )
				return;

			long c = d.getCapacity();
			long u = d.getDfsUsed();
			long nu = d.getNonDfsUsed();
			long r = d.getRemaining();
			String percentUsed = StringUtils.limitDecimalTo2(d.getDfsUsedPercent());    
			String percentRemaining = StringUtils.limitDecimalTo2(d.getRemainingPercent());    

			String adminState = (d.isDecommissioned() ? "Decommissioned" :
				(d.isDecommissionInProgress() ? "Decommission In Progress":
				"In Service"));

			long timestamp = d.getLastUpdate();
			long currentTime = System.currentTimeMillis();
			out.print("<td class=\"lastcontact\"> " +
					((currentTime - timestamp)/1000) +
					"<td class=\"adminstate\">" +
					adminState +
					"<td align=\"right\" class=\"capacity\">" +
					StringUtils.limitDecimalTo2(c*1.0/diskBytes) +
					"<td align=\"right\" class=\"used\">" +
					StringUtils.limitDecimalTo2(u*1.0/diskBytes) +      
					"<td align=\"right\" class=\"nondfsused\">" +
					StringUtils.limitDecimalTo2(nu*1.0/diskBytes) +      
					"<td align=\"right\" class=\"remaining\">" +
					StringUtils.limitDecimalTo2(r*1.0/diskBytes) +      
					"<td align=\"right\" class=\"pcused\">" + percentUsed +
					"<td class=\"pcused\">" +
					ServletUtil.percentageGraph( (int)Double.parseDouble(percentUsed) , 100) +
					"<td align=\"right\" class=\"pcremaining`\">" + percentRemaining +
					"<td title=" + "\"blocks scheduled : " + d.getBlocksScheduled() + 
					"\" class=\"blocks\">" + d.numBlocks() + "\n");
}



public void generateDFSNodesList(JspWriter out, 
		NameNode nn,
		HttpServletRequest request)
throws IOException {
	ArrayList<DatanodeDescriptor> live = new ArrayList<DatanodeDescriptor>();    
	ArrayList<DatanodeDescriptor> dead = new ArrayList<DatanodeDescriptor>();
	nn.getNamesystem().DFSNodesStatus(live, dead);

	whatNodes = request.getParameter("whatNodes"); // show only live or only dead nodes
	sorterField = request.getParameter("sorter/field");
	sorterOrder = request.getParameter("sorter/order");
	if ( sorterField == null )
		sorterField = "name";
	if ( sorterOrder == null )
		sorterOrder = "ASC";

	JspHelper.sortNodeList(live, sorterField, sorterOrder);
	JspHelper.sortNodeList(dead, "name", "ASC");

	// Find out common suffix. Should this be before or after the sort?
	String port_suffix = null;
	if ( live.size() > 0 ) {
		String name = live.get(0).getName();
		int idx = name.indexOf(':');
		if ( idx > 0 ) {
			port_suffix = name.substring( idx );
		}

		for ( int i=1; port_suffix != null && i < live.size(); i++ ) {
			if ( live.get(i).getName().endsWith( port_suffix ) == false ) {
				port_suffix = null;
				break;
			}
		}
	}

	counterReset();

	try {
		Thread.sleep(1000);
	} catch (InterruptedException e) {}

	if (live.isEmpty() && dead.isEmpty()) {
		out.print("There are no datanodes in the cluster");
	}
	else {

		int nnHttpPort = nn.getHttpAddress().getPort();
		out.print( "<div id=\"dfsnodetable\"> ");
		if(whatNodes.equals("LIVE")) {

			out.print( 
					"<a name=\"LiveNodes\" id=\"title\">" +
					"Live Datanodes : " + live.size() + "</a>" +
			"<br><br>\n<table border=1 cellspacing=0>\n" );

			counterReset();

			if ( live.size() > 0 ) {

				if ( live.get(0).getCapacity() > 1024 * diskBytes ) {
					diskBytes *= 1024;
					diskByteStr = "TB";
				}

				out.print( "<tr class=\"headerRow\"> <th " +
						NodeHeaderStr("name") + "> Node <th " +
						NodeHeaderStr("lastcontact") + "> Last <br>Contact <th " +
						NodeHeaderStr("adminstate") + "> Admin State <th " +
						NodeHeaderStr("capacity") + "> Configured <br>Capacity (" + 
						diskByteStr + ") <th " + 
						NodeHeaderStr("used") + "> Used <br>(" + 
						diskByteStr + ") <th " + 
						NodeHeaderStr("nondfsused") + "> Non DFS <br>Used (" + 
						diskByteStr + ") <th " + 
						NodeHeaderStr("remaining") + "> Remaining <br>(" + 
						diskByteStr + ") <th " + 
						NodeHeaderStr("pcused") + "> Used <br>(%) <th " + 
						NodeHeaderStr("pcused") + "> Used <br>(%) <th " +
						NodeHeaderStr("pcremaining") + "> Remaining <br>(%) <th " +
						NodeHeaderStr("blocks") + "> Blocks\n" );

				JspHelper.sortNodeList(live, sorterField, sorterOrder);
				for ( int i=0; i < live.size(); i++ ) {
					generateNodeData(out, live.get(i), port_suffix, true, nnHttpPort);
				}
			}
			out.print("</table>\n");
		} else {

			out.print("<br> <a name=\"DeadNodes\" id=\"title\"> " +
					" Dead Datanodes : " +dead.size() + "</a><br><br>\n");

			if ( dead.size() > 0 ) {
				out.print( "<table border=1 cellspacing=0> <tr id=\"row1\"> " +
				"<td> Node \n" );

				JspHelper.sortNodeList(dead, "name", "ASC");
				for ( int i=0; i < dead.size() ; i++ ) {
					generateNodeData(out, dead.get(i), port_suffix, false, nnHttpPort);
				}

				out.print("</table>\n");
			}
		}
		out.print("</div>");
	}
}%>

<%
NameNode nn = (NameNode)application.getAttribute("name.node");
FSNamesystem fsn = nn.getNamesystem();
String namenodeLabel = nn.getNameNodeAddress().getHostName() + ":" + nn.getNameNodeAddress().getPort();
%>

<html>

<link rel="stylesheet" type="text/css" href="/static/hadoop.css">
<title>Hadoop NameNode <%=namenodeLabel%></title>
  
<body>
<h1>NameNode '<%=namenodeLabel%>'</h1>
<%= JspHelper.getVersionTable(fsn) %>
<br />
<b><a href="/nn_browsedfscontent.jsp">Browse the filesystem</a></b><br>
<b><a href="/logs/">Namenode Logs</a></b><br>
<b><a href=/dfshealth.jsp> Go back to DFS home</a></b>
<hr>
<%
	generateDFSNodesList(out, nn, request); 
%>

<%
out.println(ServletUtil.htmlFooter());
%>
