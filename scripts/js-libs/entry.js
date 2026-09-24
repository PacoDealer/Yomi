// The real JS libraries LNReader plugins are written against, bundled for JavaScriptCore (S125).
// Replaces JSBridge's hand-written cheerio / dayjs / htmlparser2 stand-ins (RESEARCH.md §22.4, §22.14).
import './polyfills.js';
import { load } from 'cheerio';
import * as htmlparser2 from 'htmlparser2';
import dayjs from 'dayjs';
import customParseFormat from 'dayjs/plugin/customParseFormat';
import relativeTime from 'dayjs/plugin/relativeTime';
import utc from 'dayjs/plugin/utc';

dayjs.extend(customParseFormat);
dayjs.extend(relativeTime);
dayjs.extend(utc);

globalThis.__yomiLibs = { cheerio: { load }, htmlparser2, dayjs };
