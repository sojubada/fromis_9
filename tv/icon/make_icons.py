"""tvOS 아이콘 만들기: back.png(배경) + front.png(투명 배경 캐릭터) → Assets.xcassets
사용: python3 tv/icon/make_icons.py   (Pillow 필요)"""
import json, os, shutil
from PIL import Image, ImageDraw, ImageFont
H=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(H,'Assets.xcassets')
back=Image.open(os.path.join(H,'back.png')).convert('RGBA')
front=Image.open(os.path.join(H,'front.png')).convert('RGBA')
font=os.path.join(H,'..','..','fonts','Jua-Regular.ttf')

def cover(im,w,h):
    s=max(w/im.width,h/im.height);r=im.resize((round(im.width*s),round(im.height*s)),Image.LANCZOS)
    x=(r.width-w)//2;y=(r.height-h)//2;return r.crop((x,y,x+w,y+h))
def fit(im,w,h,scale=0.9,cx=0.5,by=0.97):
    c=Image.new('RGBA',(w,h),(0,0,0,0));s=min(w*scale/im.width,h*scale/im.height)
    r=im.resize((round(im.width*s),round(im.height*s)),Image.LANCZOS)
    c.alpha_composite(r,(round(w*cx-r.width/2),round(h*by-r.height)));return c
def shelf(w,h):
    c=cover(back,w,h);c.alpha_composite(fit(front,w,h,0.92,0.22,1.0))
    d=ImageDraw.Draw(c);f=ImageFont.truetype(font,round(h*0.22))
    d.text((round(w*0.62),round(h*0.5)),"한글 별밤",font=f,fill=(255,255,255),anchor="mm",stroke_width=round(h*0.012),stroke_fill=(26,30,70))
    return c.convert('RGB')
def js(path,obj):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    with open(path,'w') as f:json.dump(obj,f,indent=1)
INFO={"author":"xcode","version":1}
def stack(name,sizes):
    d=os.path.join(OUT,'App Icon & Top Shelf Image.brandassets',name+'.imagestack')
    js(os.path.join(d,'Contents.json'),{"info":INFO,"layers":[{"filename":"Front.imagestacklayer"},{"filename":"Back.imagestacklayer"}]})
    for layer in ['Front','Back']:
        ld=os.path.join(d,layer+'.imagestacklayer');js(os.path.join(ld,'Contents.json'),{"info":INFO})
        imgs=[]
        for sc,(w,h) in sizes:
            fn=layer.lower()+('@2x' if sc=='2x' else '')+'.png'
            im=cover(back,w,h) if layer=='Back' else fit(front,w,h,0.86)
            (im.convert('RGB') if layer=='Back' else im).save(os.path.join(ld,'Content.imageset',fn)) if os.makedirs(os.path.join(ld,'Content.imageset'),exist_ok=True) is None else None
            imgs.append({"idiom":"tv","scale":sc,"filename":fn})
        js(os.path.join(ld,'Content.imageset','Contents.json'),{"info":INFO,"images":imgs})
def imageset(name,sizes):
    d=os.path.join(OUT,'App Icon & Top Shelf Image.brandassets',name+'.imageset');os.makedirs(d,exist_ok=True);imgs=[]
    for sc,(w,h) in sizes:
        fn='shelf'+('@2x' if sc=='2x' else '')+'.png';shelf(w,h).save(os.path.join(d,fn));imgs.append({"idiom":"tv","scale":sc,"filename":fn})
    js(os.path.join(d,'Contents.json'),{"info":INFO,"images":imgs})
shutil.rmtree(OUT,ignore_errors=True)
js(os.path.join(OUT,'Contents.json'),{"info":INFO})
stack('App Icon',[('1x',(400,240)),('2x',(800,480))])
stack('App Icon - App Store',[('1x',(1280,768))])
imageset('Top Shelf Image',[('1x',(1920,720)),('2x',(3840,1440))])
imageset('Top Shelf Image Wide',[('1x',(2320,720)),('2x',(4640,1440))])
js(os.path.join(OUT,'App Icon & Top Shelf Image.brandassets','Contents.json'),{"info":INFO,"assets":[
 {"filename":"App Icon - App Store.imagestack","idiom":"tv","role":"primary-app-icon","size":"1280x768"},
 {"filename":"App Icon.imagestack","idiom":"tv","role":"primary-app-icon","size":"400x240"},
 {"filename":"Top Shelf Image Wide.imageset","idiom":"tv","role":"top-shelf-image-wide","size":"2320x720"},
 {"filename":"Top Shelf Image.imageset","idiom":"tv","role":"top-shelf-image","size":"1920x720"}]})
print("ok")
