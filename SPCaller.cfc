<!--- 
LICENSE 
Copyright 2008 Bob Silverberg

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

File Name: 

	SPCaller.cfc (Stored Procedure Caller)
	
Version: 1.0	

Description: 

	This component calls Stored Procedures, dynamically building the
	<cfstoredproc> and <cfprocparam> tags for you.

Usage:

	It is recommended, but not required, that this component be instantiated as a singleton.
	One of the easiest ways to do that is via Coldspring.
	
	A simple Coldspring bean definition would look like this:
	
		<bean id="SPCaller" class="path_to_cfc.SPCaller">
		   <constructor-arg name="DSN"><value>MyDatasourceName</value></constructor-arg>
		</bean>
		
	If you want to inject the component into a Service or DAO,
	it would look something like this:
		
		<bean id="MyService" class="path_to_cfc.MyService">
			<property name="SPCaller">
				<ref bean="SPCaller" />
			</property>
		</bean>
	
	You'd then need to add a setSPCaller() method in your MyService.cfc, for example:
	
		<cffunction name="setSPCaller" access="public" returntype="void" output="false" hint="I set the SPCaller.">
			<cfargument name="SPCaller" type="any" required="true" />
			<cfset variables.instance.SPCaller = arguments.SPCaller />
		</cffunction>
	
	You can also initialize the component manually, like this:
	
		<cfset SPCaller = CreateObject("component","path_to_cfc.SPCaller").Init("MyDatasourceName") />
		
	The SPCaller component has one method that you would call, callSP(),
	which accepts the following arguments:
	1. SPName - The name of your stored procedure.
    2. DataStruct - An optional argument which is a structure of data that should be
	   passed into the SP's parameters.
	   This is optional as often an SP will not have any parameters.
    3. DSN - The datasource to be used when calling the SP.  This is also optional, as it is
	   only required if you wish to override the DSN that was set via the Init() method.

	For example, to call this SP:
	
		CREATE PROCEDURE [dbo].[Test_Update]
			@id int
			,@colVarChar varchar(50)
		AS
		SET NOCOUNT ON;
	
		UPDATE	tblDataTypes
		SET		colVarChar = @colVarChar
		WHERE	id = @id
		
		SELECT 	id, colVarChar
		FROM	tblDataTypes
		WHERE	id = @id

	You could do:
	
		<cfset DataStruct = StructNew() />
		<cfset DataStruct.id = 1 />
		<cfset DataStruct.colVarChar = "New Text" />
		<cfset qryTest = SPCaller.callSP("Test_Update",DataStruct) />
	
	If you already have all of your data in a struct, for example in the attributes scope
	in Fusebox,	or from Event.getAllValues() in Model-Glue, then you can simply pass that
	struct into the DataStruct argument, which saves a lot of work.
	
	More complete documentation can be found at http://www.silverwareconsulting.com/page.cfm/SPCaller
	 	
--->

<cfcomponent>
	
	<cffunction name="Init" access="Public" returntype="any" output="false" hint="I build a new SPCaller">
		<cfargument name="DSN" type="string" required="true" hint="The name of the default datasource" />
		<cfset variables.Instance = StructNew() />
		<cfset variables.Instance.SPs = StructNew() />
		<cfset setDSN(arguments.DSN) />
		<cfreturn this />
	</cffunction>

	<cffunction name="callSP" access="public" output="false" returntype="query" hint="Calls a stored procedure automatically passing parameters to it.">
		<cfargument name="SPName" type="string" required="Yes"/>
		<cfargument name="DataStruct" type="struct" required="No" default="#StructNew()#" />
		<cfargument name="DSN" type="string" required="No" default="#getDSN()#"/>
		
		<cfset var qryReturn = QueryNew("NoResults") />
		<cfset var arrParams = 0 />
		<cfset var arrIndex = 0 />
		<cfset var useNull = 0 />
		<cfset var fieldName = 0 />
		<cfset var theValue = 0 />
		<cfset var Data = arguments.DataStruct /> <!--- Shortcut --->
		
		<!--- If the SP info does not already exist in the cache --->
		<cfif NOT StructKeyExists(variables.Instance.SPs,arguments.SPName)>
			<cfset StructInsert(variables.Instance.SPs,arguments.SPName,initSP(arguments.SPName,arguments.DSN),true)>
		</cfif>

		<!--- Store the params array in a local variable --->
		<cfset arrParams = variables.Instance.SPs[arguments.SPName] />
		
		<cfstoredproc datasource="#arguments.DSN#" procedure="#arguments.SPName#">
			<cfprocresult name="qryReturn" />
			<cfloop from="1" to="#ArrayLen(arrParams)#" step="1" index="arrIndex">
				<cfset useNull = false />
				<cfset fieldName = Replace(arrParams[arrIndex].ParamName,"@","") />
				<!--- Check to see if param exists in attributes scope OR if it's a boolean --->
				<cfif StructKeyExists(Data,fieldName) OR arrParams[arrIndex].CFType EQ "boolean">
					<!--- Format the value --->
					<cfswitch expression="#arrParams[arrIndex].CFType#">
						<cfcase value="numeric">
							<!--- Apply the Val() function to all numeric parameters --->
							<cfset theValue = Val(Data[fieldName]) />
						</cfcase>
						<cfcase value="string,binary">
							<!--- No formatting required --->
							<cfset theValue = Data[fieldName] />
						</cfcase>
						<cfcase value="boolean">
							<!--- If a bit field exists in the Data struct, apply the Val() function and pass the value
									If it doesn't exist we are assuming that its value should be passed as zero (0) - this is done to
									make processing of check boxes for bit fields simpler. --->
							<cfif StructKeyExists(Data,fieldName)>
								<cfset theValue = Val(Data[fieldName]) />
							<cfelse>
								<cfset theValue = 0>
							</cfif>
						</cfcase>
						<cfcase value="datetime">
							<!--- Apply the CreateODBCDateTime() function to all datetime parameters if they exist in the
								Data struct and are valid dates, otherwise pass the value as NULL --->
							<cfif Len(Data[fieldName]) AND IsDate(Data[fieldName])>
								<cfset theValue = CreateODBCDateTime(Data[fieldName]) />
							<cfelse>
								<cfset theValue = "NULL">
							</cfif>
						</cfcase>
					</cfswitch>
				<cfelse>
					<cfset theValue = "NULL">
					<cfset useNull = true>
				</cfif>
				<cfif StructKeyExists(arrParams[arrIndex],"CFSQLScale")>
					<cfprocparam cfsqltype="#arrParams[arrIndex].CFSQLType#" value="#theValue#" scale="#arrParams[arrIndex].CFSQLScale#" null="#useNull#">
				<cfelse>
					<cfprocparam cfsqltype="#arrParams[arrIndex].CFSQLType#" value="#theValue#" null="#useNull#">
				</cfif>
			</cfloop>
		
		</cfstoredproc>
		
		<cfreturn qryReturn />
	</cffunction>

	<cffunction name="initSP" access="public" output="false" returntype="array" hint="Returns an array which contains info about a SPs parameters.  This array can be used by the callSP method to call the SP.">
		<cfargument name="SPName" type="string" required="Yes" />
		<cfargument name="DSN" type="string" required="Yes" />
		
		<cfset var arrParams = ArrayNew(1) />
		<cfset var qryGetParams = "">
		<cfset var theParam = 0 />
		
		<!--- Retrieve info about the SP's parameters from the database --->
		<cfstoredproc datasource="#arguments.DSN#" procedure="sp_sproc_columns">
			<cfprocresult name="qryGetParams">
			<cfprocparam cfsqltype="CF_SQL_VARCHAR" value="#arguments.SPName#">
		</cfstoredproc>
		
		<cfif qryGetParams.RecordCount>
			<cfloop query="qryGetParams">
				<!--- Process only INPUT parameters (Column_Type = 1) --->
				<cfif qryGetParams.Column_Type EQ "1">
					<cfset theParam = StructNew() />
					<cfset theParam.SQLType = qryGetParams.Type_Name />
					<!--- Calculate the type, as required by callSP(), and place it in the struct --->
					<cfswitch expression="#qryGetParams.Type_Name#">
						<cfcase value="bit">
							<cfset theParam.CFType = "boolean" />
							<cfset theParam.CFSQLType = "CF_SQL_BIT" />
						</cfcase>
						<cfcase value="tinyint,smallint,int,bigint,decimal,numeric,float,real,smallmoney,money">
							<cfset theParam.CFType = "numeric" />
							<cfswitch expression="#qryGetParams.Type_Name#">
								<cfcase value="tinyint">
									<cfset theParam.CFSQLType = "CF_SQL_TINYINT" />
								</cfcase>
								<cfcase value="smallint">
									<cfset theParam.CFSQLType = "CF_SQL_SMALLINT" />
								</cfcase>
								<cfcase value="int,bigint">
									<cfset theParam.CFSQLType = "CF_SQL_INTEGER" />
								</cfcase>
								<cfcase value="float">
									<cfset theParam.CFSQLType = "CF_SQL_FLOAT" />
								</cfcase>
								<cfcase value="real">
									<cfset theParam.CFSQLType = "CF_SQL_REAL" />
								</cfcase>
								<cfcase value="numeric">
									<cfset theParam.CFSQLType = "CF_SQL_NUMERIC" />
								</cfcase>
								<cfcase value="smallmoney,money,decimal">
									<cfset theParam.CFSQLType = "CF_SQL_DECIMAL" />
								</cfcase>
							</cfswitch>
							<cfif ListFindNoCase("decimal,numeric",qryGetParams.Type_Name)>
								<cfset theParam.SQLType = qryGetParams.Type_Name & "(" & qryGetParams.Precision & "," & qryGetParams.Scale & ")" />
								<cfset theParam.CFSQLScale = qryGetParams.Scale />
							<cfelseif ListFindNoCase("smallmoney,money",qryGetParams.Type_Name)>
								<cfset theParam.CFSQLScale = 4 />
							</cfif>
						</cfcase>
						<cfcase value="smalldatetime,datetime">
							<cfset theParam.CFType = "datetime" />
							<cfset theParam.CFSQLType = "CF_SQL_TIMESTAMP" />
						</cfcase>
						<cfcase value="char,nchar,varchar,nvarchar,text,ntext,sql_variant">
							<cfset theParam.CFType = "string" />
							<cfswitch expression="#qryGetParams.Type_Name#">
								<cfcase value="char,nchar">
									<cfset theParam.CFSQLType = "CF_SQL_CHAR" />
								</cfcase>
								<cfcase value="varchar,nvarchar,sql_variant">
									<cfset theParam.CFSQLType = "CF_SQL_VARCHAR" />
								</cfcase>
								<cfcase value="text,ntext">
									<cfset theParam.CFSQLType = "CF_SQL_LONGVARCHAR" />
								</cfcase>
								<cfcase value="uniqueidentifier">
									<cfset theParam.CFSQLType = "CF_SQL_IDSTAMP" />
								</cfcase>
							</cfswitch>
							<cfif ListFindNoCase("char,nchar,varchar,nvarchar",qryGetParams.Type_Name)>
								<cfset theParam.SQLType = qryGetParams.Type_Name & "(" & qryGetParams.Precision & ")" />
							</cfif>
						</cfcase>
						<cfcase value="binary,image,varbinary">
							<cfset theParam.CFType = "binary" />
							<cfswitch expression="#qryGetParams.Type_Name#">
								<cfcase value="binary">
									<cfset theParam.CFSQLType = "CF_SQL_BINARY" />
								</cfcase>
								<cfcase value="image">
									<cfset theParam.CFSQLType = "CF_SQL_LONGVARBINARY" />
								</cfcase>
								<cfcase value="varbinary">
									<cfset theParam.CFSQLType = "CF_SQL_VARBINARY" />
								</cfcase>
							</cfswitch>
							<cfif ListFindNoCase("binary,varbinary",qryGetParams.Type_Name)>
								<cfset theParam.SQLType = qryGetParams.Type_Name & "(" & qryGetParams.Precision & ")" />
							</cfif>
						</cfcase>
					</cfswitch>
					<!--- Was a valid parameter type found? --->
					<cfif StructKeyExists(theParam,"CFType")>
						<!--- Set the parameter name and add it to the array --->
						<cfset theParam.ParamName = qryGetParams.Column_Name />
						<cfset ArrayAppend(arrParams,theParam) />
					</cfif>				
				</cfif>
			</cfloop>
		</cfif>
		
		<cfreturn arrParams />
	</cffunction>

	<cffunction name="setDSN" returntype="void" access="private" output="false">
		<cfargument name="DSN" type="any" required="true" />
		<cfset variables.Instance.DSN = arguments.DSN />
	</cffunction>
	<cffunction name="getDSN" access="public" output="false" returntype="any">
		<cfreturn variables.Instance.DSN />
	</cffunction>

	<cffunction name="getSPs" access="public" output="false" returntype="struct">
		<cfreturn variables.Instance.SPs />
	</cffunction>

</cfcomponent>
