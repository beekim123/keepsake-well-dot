// The center is deliberately quiet; only the fixed nine-slice corners have ornament.
export const assets = [{
  meta: { id: 'ui.panel.default', file: 'ui/panel-default.png', size: [16, 16], frames: 1, anchor: [0, 0], animations: {}, nineSlice: [4, 4, 4, 4] },
  draw(g) {
    g.rect(2,0,12,16,'ink').rect(0,2,16,12,'ink');
    g.rect(2,1,12,14,'rope0').rect(1,2,14,12,'rope0');
    g.rect(3,2,10,12,'rope2').rect(2,3,12,10,'rope2');
    g.line(3,2,12,2,'rope4').line(2,3,2,12,'rope3');
    g.rect(3,3,10,10,'ink2').rect(4,4,8,8,'deep0');
    g.line(3,13,12,13,'rope1').line(13,3,13,12,'rope1');
    g.px(2,2,'rope3').px(13,2,'rope3').px(2,13,'rope1').px(13,13,'rope1');
  },
}];
