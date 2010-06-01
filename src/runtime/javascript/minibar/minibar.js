// minibar.js, assumes that support.js has also been loaded

/* --- Configuration -------------------------------------------------------- */


var default_server="http://www.grammaticalframework.org:41296"
var tree_icon=default_server+"/translate/se.chalmers.cs.gf.gwt.TranslateApp/tree-btn.png";

// default values for options:
var options={
    server: default_server,
    grammars_url: null, // if left null, start_minibar() fills in server+"/grammars/"
    grammar_list: null, // if left null, start_minibar() will fetch a list from the server
    show_abstract: false,
    show_trees: false,
    show_grouped_translations: true,
    delete_button_text: "⌫",
    try_google: true,
    feedback_button: false
}

/* --- Grammar access object ------------------------------------------------ */

var server = {
    // State variables (private):
    current_grammar_url: options.grammars_url+"Foods.pgf",
    // Methods:
    switch_grammar: function(grammar_name) {
	this.current_grammar_url=options.grammars_url+grammar_name;
    },
    
    get_grammarlist: function(cont_name) {
	jsonp(options.grammars_url+"grammars.cgi",cont_name);
    },
    get_languages: function(cont_name) {
	jsonp(this.current_grammar_url,cont_name);
    },
    get_random: function(cont_name) {
	jsonp(this.current_grammar_url+"?command=random&random="+Math.random(),cont_name);
    },
    linearize: function(tree,to,cont_name) {
	jsonp(this.current_grammar_url+"?command=linearize&tree="
	      +encodeURIComponent(tree)+"&to="+to,cont_name)
    },
    complete: function(from,input,cont_name) {
	jsonp(this.current_grammar_url
	      +"?command=complete"
	      +"&from="+encodeURIComponent(from)
	      +"&input="+encodeURIComponent(input),
	      cont_name);

    },
    translate: function(from,input,cont_name) {
	jsonp(this.current_grammar_url
	      +"?command=translate"
	      +"&from="+encodeURIComponent(from)
	      +"&input="+encodeURIComponent(input),
	      cont_name)
    },
    translategroup: function(from,input,cont_name) {
	jsonp(this.current_grammar_url
	      +"?command=translategroup"
	      +"&from="+encodeURIComponent(from)
	      +"&input="+encodeURIComponent(input),
	      cont_name)
    }

};

/* --- Initialisation ------------------------------------------------------- */

function start_minibar(opts) { // typically called when the HTML document is loaded
    if(opts) for(var o in opts) options[o]=opts[o];
    var surface=div_id("surface");
    //surface.setAttribute("onclick","add_typed_input(this)");
    appendChildren(element("minibar"),
		   [div_id("menubar"),
		    surface,
		    div_id("words"),
		    div_id("translations")]);
    if(!options.grammars_url) options.grammars_url=options.server+"/grammars/";
    if(options.grammar_list) show_grammarlist(options.grammar_list)
    else server.get_grammarlist("show_grammarlist");
}


/* --- Functions ------------------------------------------------------------ */

function show_grammarlist(grammars) {
    var menubar=element("menubar");
    menubar.innerHTML="";
    if(grammars.length>1) {
	var menu=empty("select");
	for(var i=0;i<grammars.length;i++) {
	    var opt=empty("option");
	    opt.setAttribute("value",grammars[i]);
	    opt.innerHTML=grammars[i];
	    menu.appendChild(opt);
	}
	menu.setAttribute("onchange","new_grammar(this)");
	menubar.innerHTML="Grammar: ";
	menubar.appendChild(menu);
    }
    appendChildren(menubar,
		   [text(" From: "), empty_id("select","language_menu"),
		    text(" To: "), empty_id("select","to_menu"),
		    button(options.delete_button_text,"delete_last()"),
		    button("Clear","clear_all()"),
		    button("Random","generate_random()")]);
    select_grammar(grammars[0]);
}

function new_grammar(menu) {
  select_grammar(menu.options[menu.selectedIndex].value);
}

function select_grammar(grammar_name) {
    server.switch_grammar(grammar_name);
    server.get_languages("show_languages");
}

function langpart(conc,abs) { // langpart("FoodsEng","Food") == "Eng"
    return hasPrefix(conc,abs) ? conc.substr(abs.length) : conc;
}

function show_languages(grammar) {
    var r="";
    var lang=grammar.languages;
    var menu=element("language_menu");
    menu.setAttribute("onchange","new_language(this)");
    menu.grammar=grammar;
    menu.innerHTML="";

    for(var i=0; i<lang.length; i++)
	if(lang[i].canParse && !hasPrefix(lang[i].name,"Disamb"))
	    menu.appendChild(option(langpart(lang[i].name,grammar.name),""+i));

    var to=element("to_menu");
    to.langmenu=menu;
    to.setAttribute("onchange","change_tolang(this)");
    to.innerHMTL="";
    to.appendChild(option("All","-1"));
    for(var i=0; i<lang.length; i++)
	if(!hasPrefix(lang[i].name,"Disamb"))
	    to.appendChild(option(langpart(lang[i].name,grammar.name),lang[i].name));
    new_language(menu);
}

function new_language(menu) {
  var ix=menu.options[menu.selectedIndex].value;
  var langname=menu.grammar.languages[ix].name;
  menu.current={from: langname, input: ""};
  clear_all();
}

function change_tolang(to_menu) {
    get_translations(to_menu.langmenu)
}

function clear_all1() {
    var menu=element("language_menu");
    menu.current.input="";
    menu.previous=null;
    var surface=element("surface");
    surface.innerHTML="";
    surface.typed=null;
    element("translations").innerHTML="";
    return menu;
}

function clear_all() {
  get_completions(clear_all1());
}

function delete_last() {
  var menu=element("language_menu");
  if(menu.previous) {
    menu.current.input=menu.previous.input;
    menu.previous=menu.previous.previous;
    var s=element("surface");
    if(s.typed) {
	s.removeChild(s.typed.previousSibling);
	s.typed.focus();
    }
    else
	s.removeChild(s.lastChild);
    element("translations").innerHTML="";
    get_completions(menu);
  }
}

function add_typed_input(surface) {
    if(surface.typed)
	inp=surface.typed;
    else {
	var inp=empty("input","type","text");
	//inp.setAttribute("onclick","return false;"); // Don't propagate click to surface
	inp.setAttribute("onkeyup","complete_typed(this)");
	inp.setAttribute("onchange","finish_typed(this)");
	surface.appendChild(inp);
	surface.typed=inp;
    }
    inp.focus();
}

function remove_typed_input(surface) {
    if(surface.typed) {
	surface.typed.parentNode.removeChild(surface.typed);
	surface.typed=null;
    }
}

function complete_typed(inp) {
    var menu=element("language_menu");
    var c=menu.current;
    if(!inp.completing || inp.completing!=inp.value) {
	inp.completing=inp.value;
	server.complete(c.from,c.input+inp.value,"show_completions");
    }
}

function finish_typed(inp) {
    //alert("finish_typed "+inp.value);
    var box=element("words");
    var w=inp.value+" ";
    if(box.completions.length==1)
	add_word(box.completions[0]);
    else if(elem(w,box.completions))
	add_word(w);
}

function generate_random() {
    server.get_random("lin_random");
}

function lin_random(abs) {
  var menu=element("language_menu");
  var lang=menu.current.from;
  server.linearize(abs[0].tree,lang,"show_random");
}

function show_random(random) {
  var menu=clear_all1();
  var words=random[0].text.split(" ");
  for(var i=0;i<words.length;i++)
    add_word1(menu,words[i]+" ");
  element("words").innerHTML="...";
  get_completions(menu);
}

function get_completions(menu) {
  var c=menu.current;
  server.complete(c.from,c.input,"show_completions");
}

function word(s) {
  //var w=div_class("word",text(s));
  //w.setAttribute("onclick",'add_word("'+s+'")');
  //return w;
  return button(s,'add_word("'+s+'")');
}

function add_word1(menu,s) {
    menu.previous={ input: menu.current.input, previous: menu.previous };
    menu.current.input+=s;
    var w=span_class("word",text(s));
    var surface=element("surface");
    if(surface.typed) {
	surface.typed.value="";
	surface.insertBefore(w,surface.typed);
    }
    else
	surface.appendChild(w);
}

function add_word(s) {
  var menu=element("language_menu");
  add_word1(menu,s);
  element("words").innerHTML="...";
  get_completions(menu);
}

function show_completions(completions) {
  var box=element("words");
  var menu=element("language_menu");
  var prefixlen=menu.current.input.length;
  var emptycnt=0;
  box.innerHTML="";
  box.completions=[];
  for(var i=0;i<completions.length;i++) {
    var s=completions[i].text.substring(prefixlen);
    box.completions[i]=s;
    if(s.length>0) box.appendChild(word(s));
    else emptycnt++;
  }
  if(emptycnt>0) get_translations(menu);
  else {
    var trans=element("translations");
    trans.innerHTML="";
    extra_actions(menu.grammar,trans,target_lang());
  }
  var surface=element("surface");
  if(surface.typed && emptycnt==completions.length) {
      if(surface.typed.value=="") remove_typed_input(surface);
  }
  else add_typed_input(surface);
}

function get_translations(menu) {
    var c=menu.current;
    if(options.show_grouped_translations)
	server.translategroup(c.from,c.input,"show_groupedtranslations");
    else
	server.translate(c.from,c.input,"show_translations");
}

function tdt(tree_btn,txt) {
    return options.show_trees ? tda([tree_btn,txt]) : td(txt);
}

function target_lang() {
    var to_menu=element("to_menu");
    var grammar=element("language_menu").grammar;
    return langpart(to_menu.options[to_menu.selectedIndex].value,grammar.name);
}

function show_translations(translations) {
  var trans=element("translations");
  var grammar=element("language_menu").grammar;
  var to=target_lang();
  var cnt=translations.length;
  //trans.translations=translations;
  trans.single_translation=[];
  trans.innerHTML="";
  trans.appendChild(wrap("h3",text(cnt<1 ? "No translations?" :
				   cnt>1 ? ""+cnt+" translations:":
				   "One translation:")));
  for(p=0;p<cnt;p++) {
    var t=translations[p];
    var lin=t.linearizations;
    var tbody=empty("tbody");
    if(options.show_abstract && t.tree)
      tbody.appendChild(tr([th(text("Abstract: ")),
			    tdt(abstree_button(t.tree),text(" "+t.tree))]));
    for(var i=0;i<lin.length;i++) 
	if(to=="-1" || lin[i].to==to)
	    tbody.appendChild(tr([th(text(langpart(lin[i].to,grammar.name)+": ")),
				  tdt(parsetree_button(t.tree,lin[i].to),
				      text(lin[i].text))]));
    trans.appendChild(wrap("table",tbody));
  }
  extra_actions(grammar,trans,to);
}

function show_groupedtranslations(translations) {
    var trans=element("translations");
    var grammar=element("language_menu").grammar;
    var to=target_lang();
    var cnt=translations.length;
    //trans.translations=translations;
    trans.single_translation=[];
    trans.innerHTML="";
    for(p=0;p<cnt;p++) {
	var t=translations[p];
	if(to=="-1" || t.to==to) {
	    var lin=t.linearizations;
	    var tbody=empty("tbody");
	    if(to=="-1") tbody.appendChild(tr([th(text(t.to+":"))]));
	    for(var i=0;i<lin.length;i++) {
		if(to!="-1") trans.single_translation[i]=lin[i].text;
		tbody.appendChild(tr([(text(lin[i].text))]));
		if (lin.length > 1) tbody.appendChild(tr([(text(lin[i].tree))]));
	    }
	    trans.appendChild(wrap("table",tbody));
	}
    }
    extra_actions(grammar,trans,to);
}

function abstree_button(abs) {
  var i=img(tree_icon);
  i.setAttribute("onclick","toggle_img(this)");
  i.other=server.current_grammar_url+"?command=abstrtree&tree="+encodeURIComponent(abs);
  return i;
}

function parsetree_button(abs,lang) {
  var i=img(tree_icon);
  i.setAttribute("onclick","toggle_img(this)");
  i.other=server.current_grammar_url
          +"?command=parsetree&from="+lang+"&tree="+encodeURIComponent(abs);
  return i;
}

function toggle_img(i) {
  var tmp=i.src;
  i.src=i.other;
  i.other=tmp;
}


function extra_actions(grammar,trans,to) {
    if(options.try_google) try_google(grammar,trans,to);
    if(options.feedback_button) feedback_button(trans);
}

function try_google(grammar,trans,to) {
    var menu=element("language_menu");
    var c=menu.current;
    var url="http://translate.google.com/?sl="+langpart(c.from,grammar.name);
    if(to!="-1") url+="&tl="+to;
    url+="&q="+encodeURIComponent(c.input);
    var link=empty("a","href",url);
    link.innerHTML="Try this sentence in Google Translate";
    link.setAttribute("target","translate.google.com");
    trans.appendChild(link);
}

function feedback_button(trans) {
    trans.appendChild(text(" "));
    trans.appendChild(button("Feedback","open_feedback()"));
}

function open_feedback() {
    window.open("feedback.html",'feedback','toolbar=no,location=no,status=no,menubar=no');
}

function setField(form,name,value) {
    form[name].value=value;
    var el=element(name);
    if(el) el.innerHTML=value;
}

function opener_element(id) { with(window.opener) return element(id); }

function prefill_feedback_form() {
    var to_menu=opener_element("to_menu");
    var trans=opener_element("translations");
    var menu=to_menu.langmenu;
    var grammar=menu.grammar;
    var gn=grammar.name;
    var form=document.forms.namedItem("feedback");
    var from=langpart(menu.current.from,gn);
    var to=langpart(to_menu.options[to_menu.selectedIndex].value,gn);

    setField(form,"grammar",gn);
    setField(form,"from",from);
    setField(form,"input",menu.current.input);
    setField(form,"to",to=="-1" ? "All" : to);
    if(to=="-1") 
	element("translation_box").style.display="none";
    else 
	setField(form,"translation",trans.single_translation.join(" / "));

    // Browser info:
    form["inner_size"].value=window.innerWidth+"×"+window.innerHeight;
    form["outer_size"].value=window.outerWidth+"×"+window.outerHeight;
    form["screen_size"].value=screen.width+"×"+screen.height;
    form["available_screen_size"].value=screen.availWidth+"×"+screen.availHeight;
    form["color_depth"].value=screen.colorDepth;
    form["pixel_depth"].value=screen.pixelDepth;

    window.focus();
}

/*
se.chalmers.cs.gf.gwt.TranslateApp/align-btn.png

GET /grammars/Foods.pgf?&command=abstrtree&tree=Pred+(This+Fish)+(Very+Fresh)
GET /grammars/Foods.pgf?&command=parsetree&tree=Pred+(This+Fish)+Expensive&from=FoodsAfr
GET /grammars/Foods.pgf?&command=alignment&tree=Pred+(This+Fish)+Expensive
*/
