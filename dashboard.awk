# Dashboard renderer. Run by linux_health.sh using the system awk command.
# Its input contains real sample rows only. No demonstration readings are injected.
BEGIN {
    FS=","; names[2]="CPU"; names[3]="Memory"; names[4]="Root disk";
    limits[2]=cpu_limit; limits[3]=mem_limit; limits[4]=disk_limit;
    colors[2]="#41d6b0"; colors[3]="#a9a1ff"; colors[4]="#f5ba72";
}
{
    n++; times[n]=$1;
    for(c=2;c<=4;c++) value[c,n]=$c;
}
function model(c, i,x,y,sx,sy,sxx,sxy,syy,dx,dy,b) {
    if(n<20 || times[n]-times[1]<60) return 0;
    for(i=1;i<=n;i++) {
        x=times[i]-times[1]; y=value[c,i];
        sx+=x; sy+=y; sxx+=x*x; sxy+=x*y; syy+=y*y;
    }
    dx=n*sxx-sx*sx; dy=n*syy-sy*sy;
    if(dx<=0)return 0;
    slope[c]=(n*sxy-sx*sy)/dx;
    b=(sy-slope[c]*sx)/n;
    predicted[c]=b+slope[c]*(times[n]-times[1]+60);
    if(predicted[c]<0)predicted[c]=0; if(predicted[c]>100)predicted[c]=100;
    r2[c]=(dy>0 ? (n*sxy-sx*sy)^2/(dx*dy) : 0);
    if(r2[c]>1)r2[c]=1;
    return 1;
}
function metric_cards( c,out,badge,warning) {
    for(c=2;c<=4;c++) {
        warning=value[c,n]>=limits[c];
        badge=warning ? "Threshold reached" : "Below threshold";
        out=out sprintf("<article class=\"metric %s\" style=\"--accent:%s\"><div class=\"metric-top\"><span>%s usage</span><span class=\"metric-symbol\">%s</span></div><div class=\"metric-value\">%.2f<span>%%</span></div><div class=\"meter\"><i style=\"width:%.2f%%\"></i></div><div class=\"metric-bottom\"><span class=\"%s\">%s</span><span>Limit %s%%</span></div></article>", warning?"warning":"",colors[c],names[c],c==2?"CPU":(c==3?"RAM":"SSD"),value[c,n],value[c,n],warning?"amber":"muted",badge,limits[c]);
    }
    return out;
}
function chart( c,i,x,y,p,out,span,tick) {
    out="<svg class=\"chart\" viewBox=\"0 0 960 260\" role=\"img\" aria-label=\"Measured CPU, memory and disk usage from this run\">";
    for(tick=0;tick<=100;tick+=25) {
        y=218-tick*1.8;
        out=out sprintf("<line x1=\"50\" x2=\"936\" y1=\"%.1f\" y2=\"%.1f\" stroke=\"#283441\"/><text x=\"36\" y=\"%.1f\" text-anchor=\"end\" fill=\"#8b9ba9\" font-size=\"11\">%s%%</text>",y,y,y+4,tick);
    }
    span=times[n]-times[1]; if(span<=0)span=1;
    for(c=2;c<=4;c++) {
        p="";
        for(i=1;i<=n;i++) {
            x=50+886*(times[i]-times[1])/span; y=218-1.8*value[c,i];
            p=p sprintf("%.2f,%.2f ",x,y);
        }
        out=out sprintf("<polyline fill=\"none\" stroke=\"%s\" stroke-width=\"2.5\" stroke-linejoin=\"round\" points=\"%s\"/><circle cx=\"%.2f\" cy=\"%.2f\" r=\"4\" fill=\"%s\"/>",colors[c],p,x,y,colors[c]);
    }
    out=out "<text x=\"50\" y=\"247\" fill=\"#8b9ba9\" font-size=\"11\">" (times[n]-times[1]) " seconds ago</text><text x=\"936\" y=\"247\" text-anchor=\"end\" fill=\"#8b9ba9\" font-size=\"11\">Latest sample</text></svg>";
    return out;
}
function forecasts( c,out,state) {
    for(c=2;c<=4;c++) {
        out=out "<article class=\"forecast-card\"><span class=\"eyebrow\">" names[c] " / +60 SECONDS</span>";
        if(!ready[c]) {
            out=out "<h3>Collecting history<span class=\"loading-dots\">...</span></h3><p>Need 20 readings over at least 60 seconds.</p><div class=\"forecast-foot\">" n "/20 samples &middot; " times[n]-times[1] "s observed</div>";
        } else {
            state=pred_warning[c]?"May reach threshold":"Trend estimate";
            out=out sprintf("<h3>%.2f<span>%%</span></h3><p class=\"%s\">%s</p><div class=\"forecast-foot\">Slope %+.2f points/min &middot; R&sup2; %.2f</div>",predicted[c],pred_warning[c]?"amber":"muted",state,slope[c]*60,r2[c]);
        }
        out=out "</article>";
    }
    return out;
}
function alerts( c,out) {
    for(c=2;c<=4;c++) {
        if(value[c,n]>=limits[c])
            out=out sprintf("<div class=\"alert-row\"><span class=\"alert-marker\">!</span><div><strong>%s threshold reached</strong><p>Current %.2f%% &ge; limit %s%%</p></div><span class=\"tag\">CURRENT</span></div>",names[c],value[c,n],limits[c]);
        else if(pred_warning[c])
            out=out sprintf("<div class=\"alert-row\"><span class=\"alert-marker\">!</span><div><strong>%s may reach its threshold</strong><p>60-second estimate %.2f%% &ge; limit %s%%</p></div><span class=\"tag\">PREDICTED</span></div>",names[c],predicted[c],limits[c]);
    }
    if(out=="")out="<div class=\"empty-alert\"><span class=\"check\">&#10003;</span><div><strong>No active warnings</strong><p>Current readings are below their configured limits. Predicted warnings require sufficient history and a rising trend with R&sup2; &ge; 0.5.</p></div></div>";
    return out;
}
function table_rows( i,out) {
    for(i=n;i>=1 && i>n-5;i--)
        out=out sprintf("<tr><td>%s</td><td>%.2f%%</td><td>%.2f%%</td><td>%.2f%%</td></tr>",times[i],value[2,i],value[3,i],value[4,i]);
    return out;
}
END {
    if(n==0)exit 1;
    current_count=0; predicted_count=0;
    for(c=2;c<=4;c++) {
        ready[c]=model(c);
        pred_warning[c]=ready[c] && value[c,n]<limits[c] && slope[c]>0 && r2[c]>=0.5 && predicted[c]>=limits[c];
        if(value[c,n]>=limits[c])current_count++;
        if(pred_warning[c])predicted_count++;
    }
    token["METRIC_CARDS"]=metric_cards(); token["CHART"]=chart();
    token["FORECASTS"]=forecasts(); token["ALERTS"]=alerts(); token["TABLE_ROWS"]=table_rows();
    token["READABLE_TIME"]=readable_time; token["COUNT"]=count; token["INTERVAL"]=interval;
    token["RATE_TEXT"]=rate_text; token["WINDOW"]=n;
    token["HEALTH_LABEL"]=current_count?"Threshold reached":(predicted_count?"Predicted warning":"Below current thresholds");
    token["HEALTH_CLASS"]=(current_count || predicted_count)?"amber":"teal";
    token["WARNING_COUNT"]=current_count+predicted_count;
    token["DEMO_NOTE"]=(cpu_limit==0 || mem_limit==0 || disk_limit==0)?"<div class=\"demo-banner\">ALERT DEMONSTRATION &mdash; A threshold is set to 0%. Readings are real; the low limit deliberately triggers a warning.</div>":"";
    while((getline line < template)>0) {
        for(key in token) {
            # Literal replacement preserves HTML ampersands and avoids awk gsub replacement escapes.
            marker="{{" key "}}";
            while((pos=index(line,marker))>0)
                line=substr(line,1,pos-1) token[key] substr(line,pos+length(marker));
        }
        print line;
    }
    close(template);
}
