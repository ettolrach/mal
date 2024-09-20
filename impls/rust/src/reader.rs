use std::sync::LazyLock;

use crate::types::{Mal, MalList};

use regex::Regex;

/// A token, represented using a [`String`].
/// 
/// String is guaranteed to have at least one character.
type Token = String;
#[expect(non_camel_case_types)]
type tok = str;

static LISP_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    // Regex is known to be correct.
    Regex::new(r#"[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"#)
        .unwrap()
});

#[derive(Debug)]
struct Reader {
    position: usize,
    tokens: Vec<Token>,
}

impl Reader {
    fn new(tokens: Vec<Token>) -> Self {
        Self {
            position: 0,
            tokens,
        }
    }

    fn next(&mut self) -> Option<&tok> {
        self.position += 1;
        self.tokens.get(self.position - 1).map(String::as_str)
    }

    fn peek(&self) -> Option<&tok> {
        self.tokens.get(self.position).map(String::as_str)
    }
}

fn tokenise(s: &str) -> Vec<Token> {
    LISP_REGEX.captures_iter(s)
        .filter(|cap| !cap[1].starts_with(';'))
        .map(|cap| cap[1].to_owned())
        .collect()
}

fn read_atom(reader: &mut Reader) -> Mal {
    let token = reader.next().expect("Did not expect EOF here!");
    // Try to parse as int.
    if let Ok(n) = token.parse::<usize>() {
        return Mal::Number(n)
    }
    // Otherwise it's a symbol.
    Mal::Symbol(token.to_owned())
}

fn read_list(reader: &mut Reader) -> MalList {
    let mut list_contents: Vec<Mal> = Vec::new();
    let _ = reader.next();
    let mut token = reader.peek().expect("Did not expect EOF here!");
    while !token.starts_with(')') {
        list_contents.push(read_form(reader));
        token = reader.peek().expect("Did not expect EOF here!");
    }
    MalList(list_contents)  
}

fn read_form(reader: &mut Reader) -> Mal {
    let token = reader.peek().expect("Did not expect EOF here!");
    match token.chars().next().unwrap() {
        '(' => Mal::List(read_list(reader)),
        _ => read_atom(reader),
    }
}

#[must_use]
pub fn read_str(s: &str) -> Mal {
    let mut reader = Reader::new(tokenise(s));
    read_form(&mut reader)
}
