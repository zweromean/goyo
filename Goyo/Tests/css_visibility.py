import json
import sys
import re
import lxml.html

# Small fixture evaluator for the selectors used in this app. This does not
# emulate browser layout, specificity or WebKit. Playwright tests cover those
# once a browser executable is available.
def xpath(selector):
    parts=re.split(r'\s+(?![^\[]*\])(?![^()]*\))',selector.strip())
    output='.'
    for part in parts:
        descendant=None
        if ':has(' in part:
            part,descendant=part.split(':has(',1)
            descendant=descendant[:-1]
        tag=re.match(r'^[\w-]+',part)
        output+='//'+(tag.group(0) if tag else '*')
        for kind,value in re.findall(r'([.#])([\w-]+)',part):
            if kind=='#': output+=f'[@id="{value}"]'
            else: output+=f'[contains(concat(" ", normalize-space(@class), " "), " {value} ")]'
        for attribute in re.findall(r'\[([^\]]+)\]',part):
            match=re.fullmatch(r'([\w-]+)(\^?=)?(?:"([^"]*)"|([^\s]+))?',attribute)
            if not match: raise ValueError(attribute)
            name,operator,quoted,bare=match.groups();value=quoted if quoted is not None else bare
            if operator=='^=': output+=f'[starts-with(@{name},"{value}")]'
            elif operator=='=': output+=f'[@{name}="{value}"]'
            else: output+=f'[@{name}]'
        if descendant: output+='['+xpath(descendant)[2:]+']'
    return output

value=json.load(sys.stdin)
root=lxml.html.fromstring('<html><body>'+value['html']+'</body></html>')
hidden=[]
for selectors,content in re.findall(r'([^{}]+)\{([^{}]+)\}',value['css']):
    if 'display:none' not in content.replace(' ',''): continue
    for selector in selectors.split(','): hidden.extend(root.xpath(xpath(selector)))
found=root.xpath('//*[@id=$id]',id=value['id'])
if not found: print('false')
else:
    el=found[0]
    print(json.dumps(not any(h is el or h in el.iterancestors() for h in hidden)))
