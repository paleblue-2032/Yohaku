/// インクリメンタル検索の状態。
#[derive(Default)]
pub struct SearchState {
    pub open: bool,
    pub query: String,
    /// マッチしたバイト位置（昇順）。
    pub matches: Vec<usize>,
    /// 現在選択中のマッチ番号。
    pub current: usize,
    /// 検索欄にフォーカスを当てる要求。
    pub focus: bool,
}

impl SearchState {
    pub fn update(&mut self, text: &str) {
        self.matches.clear();
        if !self.query.is_empty() {
            for (b, _) in text.match_indices(&self.query) {
                self.matches.push(b);
            }
        }
        if self.current >= self.matches.len() {
            self.current = 0;
        }
    }

    pub fn current_match(&self) -> Option<usize> {
        self.matches.get(self.current).copied()
    }

    pub fn next(&mut self) {
        if !self.matches.is_empty() {
            self.current = (self.current + 1) % self.matches.len();
        }
    }

    pub fn prev(&mut self) {
        if !self.matches.is_empty() {
            self.current = (self.current + self.matches.len() - 1) % self.matches.len();
        }
    }
}
