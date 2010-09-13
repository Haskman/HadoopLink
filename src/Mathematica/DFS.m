(* Functions for interacting with distributed file systems. *)

getDefaultDFS[h_HadoopLink] :=
	JavaBlock@Module[
		{fs, conf},
		LoadJavaClass["org.apache.hadoop.fs.FileSystem", StaticsVisible -> True];
		conf = getConf[h];
		fs = FileSystem`get[conf];
		KeepJavaObject[fs];
		fs
	]

(* DFSFileNames: operates like FileNames, but on the distributed file system
 * referenced by HadoopLink. *)
DFSFileNames[h_HadoopLink] :=
	DFSFileNames[h, "*"]

DFSFileNames[h_HadoopLink, form_] :=
	DFSFileNames[h, form, {"/user/"<>$UserName}]

DFSFileNames[h_HadoopLink, forms_, dir_String] :=
	DFSFileNames[h, forms, {dir}]

DFSFileNames[h_HadoopLink, forms_, dirs : {__String}] :=
	JavaBlock@Module[
		{$path, conf, fs, uri, trimUrl, listMatchingNames},
		(* Double-check the JVM state *)
		InstallJava[];
		If[ !jLinkInitializedForHadoopQ[], initializeJLinkForHadoop[h]];
		LoadJavaClass["org.apache.hadoop.fs.FileSystem", StaticsVisible -> True];
		$path = LoadJavaClass["org.apache.hadoop.fs.Path"];
		fs = getDefaultDFS[h];
		(* Set up a function to trim the DFS URL off of filenames *)
		conf = getConf[h];
		uri = FileSystem`getDefaultUri[conf]@toString[];
		trimUrl[s_String] := StringDrop[s, StringLength@uri - 5];
		(* Return the filenames matching the supplied form in one directory *)
		listMatchingNames[dir_String] := Select[
			Map[
				trimUrl[#@getPath[]@toString[]]&,
				fs@listStatus[JavaNew[$path, dir]]
			],
			StringMatchQ[
				FileNameSplit[#, OperatingSystem->"Unix"][[-1]],
				forms
			]&
		];
		Flatten[listMatchingNames /@ dirs]
	]

DFSImport[h_HadoopLink, file_, "SequenceFile"] :=
	JavaBlock@Module[
		{reader, conf, path, results, record},
		InstallJava[];
		If[ !jLinkInitializedForHadoopQ[], initializeJLinkForHadoop[h]];
		conf = getConf[h];
		path = JavaNew["org.apache.hadoop.fs.Path", file];
		Check[
			reader = JavaNew["com.wolfram.hadoop.SequenceFileImportReader", conf, path];
			results = {};
			While[(record = reader@next[]) =!= Null,
				AppendTo[results, record];
			];
			reader@close[];
			results,
			die["Error reading from "<>file];
		]
	]

(* Import functionality from the DFS *)
DFSImport[h_HadoopLink, file_, args___] :=
	JavaBlock@Module[
		{fs, tempfile, $path, results},
		(* Double-check the JVM state *)
		InstallJava[];
		If[ !jLinkInitializedForHadoopQ[], initializeJLinkForHadoop[h]];
		fs = getDefaultDFS[h];
		tempfile = Close[OpenWrite[]];
		DeleteFile[tempfile];
		$path = LoadJavaClass["org.apache.hadoop.fs.Path"];
		Check[
			fs@copyToLocalFile[JavaNew[$path, file], JavaNew[$path, tempfile]],
			die["Could not write to local file"]
		];
		results = Import[tempfile, args];
		DeleteFile[tempfile];
		results
	]