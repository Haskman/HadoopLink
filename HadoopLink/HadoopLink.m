BeginPackage["HadoopLink`", {"JLink`"}]

HadoopLink::usage = "HadoopLink is an object that represents a Hadoop \
installation and configuration."

OpenHadoopLink::usage = "OpenHadoopLink[path] creates a HadoopLink object \
from the provided Hadoop installation path."

DFSFileNames::usage = "DFSFileNames[link] lists all files in the working \
directory on a distributed filesystem."

DFSImport::usage = "DFSImport[link, file] imports data from a file stored on \
distributed filesystem."

DFSExport::usage = "DFSExport[link, \"file.ext\", expr] exports data to a \
file on a distributed filesystem."

DFSAbsoluteFileName::usage = "DFSAbsoluteFileName[link, \"name\"] gives the \
full absolute version of the name for a file on the distributed filesystem."

DFSFileExistsQ::usage = "DFSFileExistsQ[link, \"name\"] gives True if the file \
with the specified name exists, and gives False otherwise."

DFSDirectoryQ::usage = "DFSDirectoryQ[link, \"name\"] gives True if the \
directory with the specified name exists, and gives False otherwise."

DFSFileType::usage = "DFSFileType[link, \"name\"] gives the type of a file: \
File, Directory, or None."

DFSFileByteCount::usage = "DFSFileByteCount[link, \"name\"] gives the number \
of bytes in a file."

DFSFileDate::usage = "DFSFileDate[link, \"name\"] gives the date and time at \
which a file was last modified."

Emit::usage = "In a map or reduce function, write out a key/value pair."

Begin["`Private`"]

$HadoopLinkPath = DirectoryName[System`Private`FindFile[$Input]];

Map[
	Import[FileNameJoin[{$HadoopLinkPath, #}]]&,
	{
		"DFS.m"
	}
];

(* Convenience function for throwing error messages. *)
die[message_String] := Throw[message, "HadoopLinkError"]

die[message_String, args__] := die[ToString@StringForm[message, args]]

HadoopLink /: Format[HadoopLink[rls__Rule]] :=
	HadoopLink["HadoopHome"/.{rls}]

property[HadoopLink[rls__Rule], name_String] :=
	name /. {rls} /. name -> Null

(* Set up a JVM and create a HadoopLink object to encapsulate
 * distributed file system access.
 *)
OpenHadoopLink[hadoopHome_String, opts___Rule] :=
	Module[
		{hadoopLink, properties},
		properties = Cases[{opts}, HoldPattern[_String -> _String]];
		hadoopLink = HadoopLink["HadoopHome"->hadoopHome, "Configuration" -> properties];
		initializeJLinkForHadoop[hadoopLink];
		hadoopLink
	]

$hadoopLinkInitializedProperty = "com.wolfram.hadooplink.initialized";

jLinkInitializedForHadoopQ[] :=
	Module[
		{initQ},
		InstallJava[];
		LoadJavaClass["java.lang.System", StaticsVisible -> True];
		initQ = System`getProperty[$hadoopLinkInitializedProperty];
		ValueQ[initQ]
	]

initializeJLinkForHadoop[h_HadoopLink] :=
	Module[
		{javaVersion, hadoopHome},
		InstallJava[];
		LoadJavaClass["java.lang.System", StaticsVisible -> True];
		(* Check Java version *)
		javaVersion = System`getProperty["java.version"];
		If[ ToExpression@StringTake[javaVersion, 3] < 1.6,
			die["HadoopLink` requires Java 6 or higher"];
		];
		(* Set up XML implementation for Hadoop *)
        System`setProperty[
			"javax.xml.parsers.DocumentBuilderFactory",
            "com.sun.org.apache.xerces.internal.jaxp.DocumentBuilderFactoryImpl"
		];
		(* Add all the Hadoop jars to the classpath *)
		hadoopHome = property[h, "HadoopHome"]; 
		AddToClassPath[Flatten@Map[
			FileNames["*.jar", #]&,
			{
				hadoopHome,
				FileNameJoin[{hadoopHome, "conf"}],
			 	FileNameJoin[{hadoopHome, "lib"}],
			 	FileNameJoin[{hadoopHome, "contrib", "streaming"}],
			 	FileNameJoin[{$HadoopLinkPath, "Java"}]
			}
		]];
		(* TODO: Add xalan to the classpath *)
		(* Mark the JVM as initialized for HadoopLink` *)
		System`setProperty[
			$hadoopLinkInitializedProperty,
			"True"
		];
	]

getConf[h_HadoopLink] :=
	JavaBlock@Module[
		{configDir, hadoopHome, conf, url},
		hadoopHome = property[h, "HadoopHome"];
		configDir = FileNameJoin[{hadoopHome, "conf"}];
		conf = JavaNew["org.apache.hadoop.conf.Configuration"];
		KeepJavaObject[conf];
		url = LoadJavaClass["java.net.URL"];
		Map[
			conf@addResource[JavaNew[url, "file://"<>#]]&,
			FileNames["*-site.xml", configDir]
		];
		(* Override with custom configuration set by this HadoopLink *)
		Map[
			conf@set[Sequence@@#] &,
			property[h, "Configuration"]
		];
		conf
	]

End[]

EndPackage[]
