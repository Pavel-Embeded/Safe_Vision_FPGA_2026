from dataclasses import dataclass
import re

@dataclass
class Token:
    start:int
    end:int
    text:str
    kind:str

OPERATORS=sorted(('<<<','>>>','===','!==','<<=','>>=','**','==','!=','<=','>=','&&','||','<<','>>','++','--','+=','-=','*=','/=','%=','&=','|=','^=','~^','^~','->','=>','*>','+:','-:','::'),key=len,reverse=True)

def tokens(text):
    out=[];i=0
    while i<len(text):
        start=i;c=text[i]
        if c.isspace():i+=1;continue
        if text.startswith('`pragma protect begin_protected',i):
            end=text.index('`pragma protect end_protected',i)+len('`pragma protect end_protected')
            out.append(Token(i,end,text[i:end],'opaque'));i=end;continue
        if text.startswith('//',i):
            end=text.find('\n',i);i=len(text)if end<0 else end;continue
        if text.startswith('/*',i):
            end=text.find('*/',i+2)
            if end<0:raise ValueError('unterminated comment')
            i=end+2;continue
        if c=='"':
            i+=1
            while i<len(text):
                if text[i]=='\\':i+=2
                elif text[i]=='"':i+=1;break
                else:i+=1
            out.append(Token(start,i,text[start:i],'string'));continue
        if c=='\\':
            i+=1
            while i<len(text)and not text[i].isspace():i+=1
            out.append(Token(start,i,text[start:i],'escaped'));continue
        match=re.match(r'[a-zA-Z_$][a-zA-Z0-9_$]*',text[i:])
        if match:
            i+=len(match.group());out.append(Token(start,i,text[start:i],'identifier'));continue
        match=re.match(r"(?:[0-9][0-9_]*\s*)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?|'[01xXzZ]",text[i:])
        if match:
            i+=len(match.group());out.append(Token(start,i,text[start:i],'number'));continue
        operator=next((op for op in OPERATORS if text.startswith(op,i)),c)
        i+=len(operator);out.append(Token(start,i,operator,'symbol'))
    return out

def apply(text,edits):
    previous=len(text)+1
    for start,end,value in sorted(edits,reverse=True):
        if end>previous:raise ValueError('overlapping edits')
        text=text[:start]+value+text[end:];previous=start
    return text
