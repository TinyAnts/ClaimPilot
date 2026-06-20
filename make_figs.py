# Canonical figure generator for the ClaimPilot paper. Run from paper/.
import json, matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np, os
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":11,"axes.spines.top":False,"axes.spines.right":False,"figure.dpi":150})
C={"primary":"#2B5C8A","accent":"#C44E34","ok":"#3C8C5A","warn":"#D9A441","grey":"#8A8F98","light":"#DCE6F1","gate":"#F6E2DC"}
F="figures/"; os.makedirs(F,exist_ok=True)
st=json.load(open("dataset/stats.json")); ev=json.load(open("dataset/eval_results.json"))

def fig1():
    seg=["Insurance /\nclaims","Production /\nherd health","Diagnostic\nlabs","Companion\nclinics"];sc=[4.25,4.15,3.28,3.25]
    fig,ax=plt.subplots(figsize=(7,3.3));ax.barh(seg[::-1],sc[::-1],color=[C["primary"],C["accent"],C["grey"],C["grey"]][::-1])
    [ax.text(v+0.04,i,f"{v:.2f}",va="center",fontsize=10) for i,v in enumerate(sc[::-1])]
    ax.set_xlim(0,5);ax.set_xlabel("Weighted suitability score (0–5)");plt.tight_layout();plt.savefig(F+"fig1_usecase_scores.png",bbox_inches="tight");plt.close()
def fig2():
    fig,ax=plt.subplots(figsize=(9.6,2.3));ax.axis("off");ax.set_xlim(0,10);ax.set_ylim(0,2.3)
    S=[("Intake","mini"),("DocExtract","mini"),("PolicyMatch","mini"),("Necessity","mini"),("Fraud/Risk","mini"),("Adjudicate","CODE"),("Notify","mini"),("Human Gate","you")]
    x=np.linspace(0.85,9.15,len(S))
    for i,(n,m) in enumerate(S):
        col=C["ok"] if m=="CODE" else (C["accent"] if m=="you" else C["primary"]);fc=C["gate"] if m=="you" else C["light"]
        ax.add_patch(FancyBboxPatch((x[i]-0.5,0.95),1.0,0.8,boxstyle="round,pad=0.02,rounding_size=0.06",lw=1.3,edgecolor=col,facecolor=fc))
        ax.text(x[i],1.43,n,ha="center",fontsize=7.6,weight="bold");ax.text(x[i],1.1,m,ha="center",fontsize=6.4,color=col)
        if i<len(S)-1: ax.add_patch(FancyArrowPatch((x[i]+0.51,1.35),(x[i+1]-0.51,1.35),arrowstyle="-|>",mutation_scale=10,color=C["grey"],lw=1))
    ax.text(5,2.05,"received → extracted → policy_checked → risk_scored → adjudication_drafted → human_review",ha="center",fontsize=8,style="italic",color="#444")
    ax.text(5,0.5,"Shared state: claims.json + immutable audit-log.jsonl   •   verify-and-retry wrapper (≤5) on every LLM stage",ha="center",fontsize=7.8,color="#444")
    plt.savefig(F+"fig2_architecture.png",bbox_inches="tight");plt.close()
def fig3():
    sn=["Intake","DocExtract","PolicyMatch","Fraud/Risk","Notify"];te=[25,0,33,80,90];ex=[100]*5;xi=np.arange(5);w=0.38
    fig,ax=plt.subplots(figsize=(7.4,3.5))
    ax.bar(xi-w/2,te,w,label="Terse prompt",color=C["warn"]);ax.bar(xi+w/2,ex,w,label="Explicit 'tool-call-or-fail' prompt",color=C["primary"])
    ax.set_xticks(xi);ax.set_xticklabels(sn,fontsize=9);ax.set_ylim(0,108);ax.set_ylabel("First-attempt tool-call success (%)")
    [ax.text(xi[i]-w/2,te[i]+2,f"{te[i]}",ha="center",fontsize=7.5,color="#555") for i in range(5)]
    ax.legend(fontsize=8.5,loc="lower center",bbox_to_anchor=(0.5,1.01),ncol=2,frameon=False)
    plt.tight_layout();plt.savefig(F+"fig3_prompt_reliability.png",bbox_inches="tight");plt.close()
def fig4():
    fig,ax=plt.subplots(figsize=(4.4,3.2));ax.bar(["LLM agent\n(gpt-5-mini)","Deterministic\ncode"],[0,100],color=[C["accent"],C["ok"]],width=0.55)
    ax.set_ylim(0,112);ax.set_ylabel("Step completion (%)");ax.text(0,4,"0 / 10",ha="center",fontsize=9,color=C["accent"]);ax.text(1,103,"100%",ha="center",fontsize=9,color=C["ok"])
    plt.tight_layout();plt.savefig(F+"fig4_adjudication.png",bbox_inches="tight");plt.close()
def fig5():
    m=["gpt-5-mini","gpt-5.4","o4-mini","gpt-5.5 (Codex)"];cp=[1,0,0,1]
    fig,ax=plt.subplots(figsize=(6,2.0));ax.imshow([cp],cmap=matplotlib.colors.ListedColormap([C["accent"],C["ok"]]),aspect="auto",vmin=0,vmax=1)
    ax.set_xticks(range(4));ax.set_xticklabels(m,fontsize=9);ax.set_yticks([])
    [ax.text(i,0,"accepts" if v else "HTTP 400",ha="center",va="center",color="white",fontsize=9,weight="bold") for i,v in enumerate(cp)]
    plt.tight_layout();plt.savefig(F+"fig5_model_compat.png",bbox_inches="tight");plt.close()
def fig6():
    cc=[0.012,0.07,0.42];lb=["Cheap tier\n(gpt-5-mini)","Mixed tier","All-frontier\n(gpt-5.5)"]
    fig,ax=plt.subplots(figsize=(5.4,3.2));ax.bar(lb,cc,color=[C["ok"],C["warn"],C["accent"]],width=0.55);ax.set_yscale("log");ax.set_ylabel("API cost / claim (USD, log)")
    [ax.text(i,v*1.12,f"${v:.3f}",ha="center",fontsize=9) for i,v in enumerate(cc)];plt.tight_layout();plt.savefig(F+"fig6_cost_per_claim.png",bbox_inches="tight");plt.close()
def fig7():
    vol=np.array([100,500,1000,5000,10000,50000]);api=vol*0.012;sv=vol*(8/60)*32
    fig,ax=plt.subplots(figsize=(7,3.4));ax.plot(vol,sv,"-o",color=C["primary"],label="Adjudicator time value saved (modeled)");ax.plot(vol,api,"-o",color=C["accent"],label="Pipeline API cost (modeled)")
    ax.set_xscale("log");ax.set_yscale("log");ax.set_xlabel("Claims per month");ax.set_ylabel("USD / month (log–log)");ax.legend(fontsize=8.5,loc="upper left")
    plt.tight_layout();plt.savefig(F+"fig7_economics.png",bbox_inches="tight");plt.close()
def fig8():
    fig,ax=plt.subplots(figsize=(8.8,8.8));ax.axis("off");ax.set_xlim(0,10);ax.set_ylim(0,14.6)
    P=C["primary"];L=C["light"];SX=5.7
    def node(cx,cy,w,h,t,sub,col,fc,tsz=9,ssz=6.8):
        ax.add_patch(FancyBboxPatch((cx-w/2,cy-h/2),w,h,boxstyle="round,pad=0.03,rounding_size=0.1",lw=1.5,edgecolor=col,facecolor=fc))
        ax.text(cx,cy+0.15,t,ha="center",fontsize=tsz,weight="bold");ax.text(cx,cy-0.26,sub,ha="center",fontsize=ssz,color="#555")
    def arr(p1,p2,dashed=False):
        ax.add_patch(FancyArrowPatch(p1,p2,arrowstyle="-|>",mutation_scale=13,color=C["grey"],lw=1.3,linestyle=("--" if dashed else "-")))
    W,H=3.5,0.86
    yI,y1,y2,y3=13.7,12.3,10.9,9.5
    node(SX,yI,3.0,0.78,"INBOX","claim documents",C["grey"],"#EEEEEE")
    node(SX,y1,W,H,"1. Intake  (LLM)","register -> received",P,L)
    node(SX,y2,W,H,"2. DocExtractor  (LLM)","parse fields -> extracted",P,L)
    node(SX,y3,W,H,"3. PolicyMatcher  (LLM)","rules -> policy_checked",P,L)
    for a,b in [(yI,y1),(y1,y2),(y2,y3)]: arr((SX,a-0.39),(SX,b+0.43))
    ny,nx,fx=7.9,3.6,7.9
    node(nx,ny,2.7,H,"4. MedicalNecessity","support note",P,L,8.4,6.4)
    node(fx,ny,2.7,H,"5. Fraud / Anomaly","risk -> risk_scored",P,L,8.4,6.4)
    arr((SX-0.5,y3-0.43),(nx+0.6,ny+0.43))
    arr((SX+0.5,y3-0.43),(fx-0.6,ny+0.43))
    ay=6.2
    node(SX,ay,W,H,"6. Adjudication  (CODE)","closed-form payout -> drafted",C["ok"],"#E1F0E7")
    arr((nx+0.6,ny-0.43),(SX-0.6,ay+0.43),dashed=True)
    arr((fx-0.6,ny-0.43),(SX+0.6,ay+0.43))
    node(SX,4.8,W,H,"7. Notifier  (LLM)","route -> human_review",P,L)
    node(SX,3.3,W,0.92,"HUMAN GATE","approve / deny / return",C["accent"],C["gate"])
    node(SX,1.7,W,0.8,"8. Notify + 9. Audit","deliver decision + log",P,L)
    for a,b in [(ay,4.8),(4.8,3.3),(3.3,1.7)]: arr((SX,a-0.43),(SX,b+0.46))
    ax.add_patch(FancyBboxPatch((0.1,8.7),1.75,4.9,boxstyle="round,pad=0.04,rounding_size=0.1",lw=1.2,edgecolor=C["warn"],facecolor="#FBF3E2"))
    ax.text(0.97,12.9,"VERIFY-\nAND-RETRY",ha="center",fontsize=7.2,weight="bold",color="#9a7016")
    ax.text(0.97,11.3,"each LLM\nstage retried\nup to 5x\nuntil status\nadvances",ha="center",fontsize=6.1,color="#7a5a1a")
    ax.add_patch(FancyBboxPatch((0.1,2.9),1.75,4.7,boxstyle="round,pad=0.04,rounding_size=0.1",lw=1.2,edgecolor=C["primary"],facecolor="#EAF1F8"))
    ax.text(0.97,6.9,"SHARED\nSTATE",ha="center",fontsize=7.2,weight="bold",color=P)
    ax.text(0.97,5.4,"claims.json\n+ append-only\naudit-log\n.jsonl",ha="center",fontsize=6.1,color="#33536f")
    ax.text(2.55,ay-0.02,"annotation\n(no status\nchange)",ha="center",fontsize=5.6,style="italic",color="#9a7016")
    plt.savefig(F+"fig8_flowchart.png",bbox_inches="tight");plt.close()
def fig9():
    fig,(a1,a2)=plt.subplots(1,2,figsize=(9,3.3));d=st["disposition"];o=["APPROVE","PARTIAL","DENY","RETURNED"];v=[d[k] for k in o]
    a1.bar(o,v,color=[C["ok"],C["warn"],C["accent"],C["grey"]]);a1.set_ylabel("Claims (n)")
    [a1.text(i,vv+0.6,str(vv),ha="center",fontsize=9) for i,vv in enumerate(v)];a1.set_title("(a) Disposition mix",fontsize=10,loc="left")
    pr=st["peril"];po=["accident","illness","orthopedic","cosmetic","wellness","unknown"];pv=[pr.get(k,0) for k in po]
    a2.barh(po[::-1],pv[::-1],color=C["primary"]);a2.set_xlabel("Claims (n)");a2.set_title("(b) Peril mix",fontsize=10,loc="left")
    [a2.text(vv+0.4,i,str(vv),va="center",fontsize=8.5) for i,vv in enumerate(pv[::-1])]
    plt.tight_layout();plt.savefig(F+"fig9_dataset.png",bbox_inches="tight");plt.close()
def fig10():
    L=ev["labels"];M=np.array([ev["cm"][k] for k in L])
    fig,ax=plt.subplots(figsize=(5.2,4.4));ax.imshow(M,cmap="Blues",aspect="auto")
    ax.set_xticks(range(4));ax.set_xticklabels(L,fontsize=9,rotation=20,ha="right");ax.set_yticks(range(4));ax.set_yticklabels(L,fontsize=9)
    ax.set_xlabel("Predicted");ax.set_ylabel("True")
    for i in range(4):
        for j in range(4):
            vv=M[i,j];ax.text(j,i,str(vv),ha="center",va="center",fontsize=12,color=("white" if vv>=6 else "#1a1a1a"),weight=("bold" if i==j else "normal"))
    for i in range(4): ax.add_patch(plt.Rectangle((i-0.5,i-0.5),1,1,fill=False,edgecolor=C["ok"],lw=2))
    plt.tight_layout();plt.savefig(F+"fig10_confusion.png",bbox_inches="tight");plt.close()
def fig11():
    cats=["APPROVE","PARTIAL","DENY","RETURNED","Overall"];acc=[100,60,40,0,50];cols=[C["ok"],C["warn"],C["accent"],C["grey"],C["primary"]]
    fig,ax=plt.subplots(figsize=(6.2,3.3));ax.bar(cats,acc,color=cols,width=0.62);ax.set_ylim(0,112);ax.set_ylabel("Disposition accuracy (%)")
    [ax.text(i,v+2,f"{v}%",ha="center",fontsize=9.5) for i,v in enumerate(acc)];ax.axhline(50,ls="--",lw=1,color="#999")
    plt.tight_layout();plt.savefig(F+"fig11_perclass_acc.png",bbox_inches="tight");plt.close()
def fig12():
    L=ev["labels"];M=np.array([ev["cm"][k] for k in L]);true=[10,10,10,10];pred=[int(M[:,j].sum()) for j in range(4)];x=np.arange(4);w=0.38
    fig,ax=plt.subplots(figsize=(6.6,3.4));ax.bar(x-w/2,true,w,label="True",color=C["grey"]);ax.bar(x+w/2,pred,w,label="Predicted",color=C["primary"])
    ax.set_xticks(x);ax.set_xticklabels(L,fontsize=9);ax.set_ylabel("Claims (n=40)")
    [ (ax.text(x[i]-w/2,true[i]+0.3,str(true[i]),ha="center",fontsize=8),ax.text(x[i]+w/2,pred[i]+0.3,str(pred[i]),ha="center",fontsize=8)) for i in range(4)]
    ax.legend(fontsize=8.5,loc="upper right");plt.tight_layout();plt.savefig(F+"fig12_dist.png",bbox_inches="tight");plt.close()

def fig13():
    import numpy as np
    L=ev["labels"];m=ev["metrics"]
    P=[m[k]["precision"] for k in L];R=[m[k]["recall"] for k in L];Fv=[m[k]["f1"] for k in L]
    x=np.arange(4);w=0.26
    fig,ax=plt.subplots(figsize=(7,3.6))
    ax.bar(x-w,P,w,label="Precision",color=C["accent"]);ax.bar(x,R,w,label="Recall",color=C["primary"]);ax.bar(x+w,Fv,w,label="F1",color=C["ok"])
    ax.set_xticks(x);ax.set_xticklabels(L,fontsize=9);ax.set_ylim(0,112);ax.set_ylabel("Score (%)")
    ax.legend(fontsize=8.5,loc="upper right",ncol=3,frameon=False)
    ax.text(0,42,"P=38%",ha="center",fontsize=7,color=C["accent"])
    plt.tight_layout();plt.savefig(F+"fig13_prf.png",bbox_inches="tight");plt.close()

ALL=[fig1,fig2,fig3,fig4,fig5,fig6,fig7,fig8,fig9,fig10,fig11,fig12,fig13]
if __name__=="__main__":
    for f in ALL: f()
    print("generated",len(ALL),"figures")
