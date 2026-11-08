#!/usr/bin/env python3
"""Build the small bilingual GitHub Pages site from reviewed copy; no remote runtime dependencies."""
import html
import json
import shutil
from pathlib import Path

root=Path(__file__).resolve().parents[1]
site=root/'site'
copy=json.loads((root/'docs/release/website-copy.json').read_text())
base='https://mdo91.github.io/runnner-iOS'
email='mahmutaoata@gmail.com'
def esc(value):return html.escape(value,quote=True)
def page(lang,slug,title,body,description):
    c=copy[lang];other='de' if lang=='en' else 'en';prefix='../' if not slug else '../../'
    links=f'<nav aria-label="{esc(c["navigation"])}"><a href="{prefix}{lang}/">{esc(c["home"])}</a><a href="{prefix}{lang}/support/">Support</a><a href="{prefix}{other}/{slug}" lang="{other}" hreflang="{other}">{"Deutsch" if other=="de" else "English"}</a></nav>'
    document=f'''<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>{esc(title)} · Runner</title><meta name="description" content="{esc(description)}"><link rel="canonical" href="{base}/{lang}/{slug}"><link rel="alternate" hreflang="{other}" href="{base}/{other}/{slug}"><link rel="stylesheet" href="{prefix}assets/site.css"><link rel="icon" href="{prefix}assets/icon.png"></head><body><header><a class="wordmark" href="{prefix}{lang}/"><span>R</span>UNNER</a>{links}</header><main>{body}</main><footer><span>© 2026 Damas Technologies LLC</span><nav aria-label="{esc(c['legalNavigation'])}"><a href="{prefix}{lang}/privacy/">{esc(c['privacyTitle'])}</a><a href="{prefix}{lang}/support/">Support</a><a href="{prefix}{lang}/legal/">{esc(c['legalTitle'])}</a></nav></footer></body></html>'''
    target=site/lang/slug;target.mkdir(parents=True,exist_ok=True);(target/'index.html').write_text(document)
for lang,c in copy.items():
    assets='../assets/'
    body=f'''<section class="hero"><div><div class="eyebrow">{esc(c['eyebrow'])}</div><h1>{esc(c['headline'])}</h1><p>{esc(c['intro'])}</p><a class="button" href="https://apps.apple.com/app/id6818808161">{esc(c['appLink'])} ↗</a><p class="small availability">{esc(c['availability'])}</p></div><img src="{assets}welcome.png" alt="{esc(c['welcomeAlt'])}" width="1254" height="1254"></section><div class="ribbon">{''.join('<span>'+esc(item)+'</span>' for item in c['ribbon'])}</div>'''
    for index,story in enumerate(c['stories'],1):
        text=f'<div><span class="step">0{index}</span><h2>{esc(story["title"])}</h2><p>{esc(story["body"])}</p><ul>'+''.join('<li>'+esc(x)+'</li>' for x in story['points'])+'</ul></div>'
        image=f'<img src="{assets}{story["image"]}.png" alt="{esc(story["alt"])}" width="1254" height="1254" loading="lazy">'
        body+=f'<section class="story {"reverse" if index%2==0 else ""}">{text+image if index%2 else image+text}</section>'
    shots=[site/'assets'/f'{lang}-{name}.png' for name in ['01-overview','06-trends','08-video']]
    if all(p.exists() for p in shots):
        body+='<section><p class="eyebrow">'+esc(c['screenshots'])+'</p><div class="screens">'+''.join(f'<img src="{assets}{p.name}" alt="{esc(c["screenshotAlt"])}" loading="lazy">' for p in shots)+'</div><p class="footnote">'+esc(c['sampleNote'])+'</p></section>'
    body+=f'<section class="privacy-band"><div><p class="eyebrow">{esc(c["privacyEyebrow"])}</p><h2>{esc(c["privacyHeadline"])}</h2><p>{esc(c["privacyIntro"])}</p><a href="privacy/">{esc(c["privacyTitle"])} ↗</a></div><img src="{assets}privacy.png" alt="" width="1254" height="1254" loading="lazy"></section><p class="footnote">{esc(c["disclaimer"])}</p>'
    page(lang,'',c['headline'],body,c['intro'])
    for slug in ['privacy','support','legal']:
        content=c[slug];body='<article class="legal"><p class="eyebrow">'+esc(content['eyebrow'])+'</p><h1>'+esc(content['title'])+'</h1>'
        for section in content['sections']:
            if section.get('heading'):body+='<h2>'+esc(section['heading'])+'</h2>'
            for paragraph in section.get('paragraphs',[]):body+='<p>'+paragraph+'</p>'
            if section.get('items'):body+='<ul>'+''.join('<li>'+x+'</li>' for x in section['items'])+'</ul>'
        body+='</article>';page(lang,slug+'/',content['title'],body,content['description'])
assets=site/'assets';assets.mkdir(parents=True,exist_ok=True)
for source,name in [('Welcome','welcome'),('Health','health'),('Insights','insights'),('Progress','progress'),('Share','share'),('Privacy','privacy')]:
    directory=root/f'Runner: Analyzer & Tracking/OnboardingAssets.xcassets/Onboarding{source}.imageset'
    images=list(directory.glob('*.png'))
    if not images:raise SystemExit(f'Missing illustration {source}')
    shutil.copyfile(images[0],assets/f'{name}.png')
shutil.copyfile(root/'Runner: Analyzer & Tracking/Assets.xcassets/AppIcon.appiconset/AppIcon.png',assets/'icon.png')
(site/'index.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=en/"><title>Runner</title><a href="en/">English</a> · <a href="de/">Deutsch</a></html>')
(site/'.nojekyll').touch()
(site/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: '+base+'/sitemap.xml\n')
(site/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join('<url><loc>'+base+'/'+lang+'/'+slug+'</loc></url>' for lang in copy for slug in ['','privacy/','support/','legal/'])+'</urlset>')
print('Built eight bilingual pages with local artwork')
