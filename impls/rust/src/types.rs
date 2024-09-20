use std::fmt::Display;

#[derive(Debug, Clone)]
pub enum Mal {
    List(MalList),
    Number(usize),
    Symbol(String),
}

impl Display for Mal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Mal::Number(n) => write!(f, "{n}"),
            Mal::Symbol(s) => write!(f, "{s}"),
            Mal::List(mal_list) => {
                write!(
                    f,
                    "{}",
                    mal_list.0
                        .iter()
                        .map(|m| format!("{m}"))
                        .collect::<Vec<String>>()
                        .join(" ")
                )
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct MalList(pub Vec<Mal>);
